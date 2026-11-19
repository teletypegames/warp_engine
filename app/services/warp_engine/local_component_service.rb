module WarpEngine
  # Turns the local components (WarpEngine::Local) on and off: queues a
  # WarpEngine::LocalOperation (#queue) that WarpEngine::LocalOperationJob
  # runs (#run), and tells their state (#list). Enabling a component enables
  # the ones its roles need first; disabling one stops those that need it.
  class LocalComponentService
    # One component as a tool sees it: +key+, +label+, +role+, the roles it
    # +requires+, a +description+, its +state+ (a WarpEngine::LocalComponent
    # state, or +unavailable+) and a +message+ (the last error, or why it is
    # unavailable).
    Line = ::Data.define(:key, :label, :role, :requires, :description, :state, :message)

    # How long a component may take to answer after its containers start.
    WAIT_SECONDS = 180

    # Returns a Line per registered component.
    def list
      reason = Local.unavailable_reason
      records = LocalComponent.all.index_by(&:key)
      Local::Components.classes.map do |klass|
        record = records[klass.key]
        Line.new(key: klass.key, label: klass.label, role: klass.role.to_s, requires: klass.requires.map(&:to_s),
                 description: klass.description, state: reason ? "unavailable" : record&.state || "off",
                 message: reason || record&.last_error)
      end
    end

    # Queues the operation +kind+ (one of WarpEngine::LocalOperation::KINDS)
    # on +target+ and returns it. Raises ArgumentError for an unknown
    # component, WarpEngine::Local::Error while the components are unavailable.
    def queue(kind, target)
      raise Local::Error, Local.unavailable_reason unless Local.available?
      raise ArgumentError, "no local component #{target}" if kind != "local_ci" && Local::Components.find(target).nil?

      operation = LocalOperation.create!(kind: kind, target: target.to_s)
      LocalOperationJob.perform_later(operation.id)
      operation
    end

    # Runs +operation+: marks it running, does its work, then succeeded with
    # its result, or failed with the error. Returns the operation.
    def run(operation)
      operation.update!(state: "running")
      result = case operation.kind
      when "enable" then enable(operation.target, operation) && {}
      when "disable" then disable(operation.target, operation) && {}
      when "remove", "purge" then remove(operation.target, operation, purge: operation.kind == "purge") && {}
      when "local_ci" then LocalCiService.new(components: self).setup(operation)
      end
      operation.update!(state: "succeeded", result: result)
      operation
    rescue StandardError => e
      operation.step!("failed: #{e.message}")
      operation.update!(state: "failed", error: e.message.truncate(2000))
      operation
    end

    # Starts the component +key+ (and what its roles need) and sets it up,
    # logging on +operation+. Returns its WarpEngine::LocalComponent. Raises
    # WarpEngine::Local::Error (the record says why, +failed+).
    def enable(key, operation)
      klass = Local::Components.find(key) or raise ArgumentError, "no local component #{key}"
      klass.requires.each { |role| ensure_role(role, operation) }
      record = LocalComponent.for(key)
      record.mark!("starting")
      start(record.component, operation)
      record.mark!("ready")
      operation.step!("#{klass.label} is ready")
      record
    rescue StandardError => e
      record&.mark!("failed", e.message)
      raise
    end

    # Returns the component of +role+ after enabling it again (the one that
    # is on, else the first registered for the role): every step is
    # idempotent, and a container made from an older spec is replaced.
    def ensure_role(role, operation)
      key = LocalComponent.where(role: role.to_s).where.not(state: "off").pick(:key) || Local::Components.for_role(role).first&.key
      raise Local::Error, "no local component plays #{role}" if key.nil?

      enable(key, operation).component
    end

    # Stops the component +key+, after the ones that need its role. Its data stays.
    def disable(key, operation)
      klass = Local::Components.find(key) or raise ArgumentError, "no local component #{key}"
      dependents(klass).each { |dependent| disable(dependent.key, operation) }
      record = LocalComponent.find_by(key: key)
      return nil unless record

      record.component.containers.reverse_each do |spec|
        operation.step!("stop #{spec.name}")
        Local.runtime.stop(spec.name)
      end
      record.mark!("stopped")
    end

    # Removes the component +key+'s containers (after the ones that need it);
    # with +purge+ its volumes and stored secrets too.
    def remove(key, operation, purge: false)
      klass = Local::Components.find(key) or raise ArgumentError, "no local component #{key}"
      dependents(klass).each { |dependent| remove(dependent.key, operation, purge: purge) }
      record = LocalComponent.find_by(key: key)
      return nil unless record

      component = record.component
      component.containers.reverse_each do |spec|
        operation.step!("remove #{spec.name}")
        Local.runtime.remove(spec.name)
      end
      return record.mark!("off") unless purge

      component.volumes.each do |volume|
        operation.step!("remove the volume #{volume}")
        Local.runtime.remove_volume(volume)
      end
      record.destroy!
    end

    private

    def dependents(klass)
      on = LocalComponent.where.not(state: %w[off]).pluck(:key)
      Local::Components.classes.select { |other| other.requires.map(&:to_s).include?(klass.role.to_s) && on.include?(other.key) }
    end

    def start(component, operation)
      runtime = Local.runtime
      runtime.ensure_network(Local.config.network)
      component.prepare(operation)
      component.containers.each do |spec|
        operation.step!("pull #{spec.image}")
        runtime.pull(spec.image)
        operation.step!("start #{spec.name}")
        runtime.run(spec, network: Local.config.network)
      end
      wait_until_healthy(component, operation)
      component.bootstrap(operation)
    end

    def wait_until_healthy(component, operation)
      operation.step!("wait for #{component.class.label}")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      until component.healthy?
        raise Local::Error, "#{component.class.label} did not answer in #{WAIT_SECONDS}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 2
      end
    end
  end
end
