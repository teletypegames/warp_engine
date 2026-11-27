module WarpEngine
  # Turns the local providers (WarpEngine::Local) on and off: queues a
  # WarpEngine::LocalTask (#queue) that WarpEngine::LocalTaskJob
  # runs (#run), and tells their state (#list). Enabling a provider enables
  # the ones its roles need first; disabling one stops those that need it.
  class LocalProviderService
    # One provider as a tool sees it: +key+, +label+, +role+, the roles it
    # +requires+, a +description+, its +state+ (a WarpEngine::LocalProvider
    # state, or +unavailable+) and a +message+ (the last error, or why it is
    # unavailable).
    Line = ::Data.define(:key, :label, :role, :requires, :description, :state, :message)

    # How long a provider may take to answer after its containers start.
    WAIT_SECONDS = 180

    # Returns a Line per registered provider.
    def list
      reason = Local.unavailable_reason
      records = LocalProvider.all.index_by(&:key)
      Local::Providers.classes.map do |klass|
        record = records[klass.key]
        Line.new(key: klass.key, label: klass.label, role: klass.role.to_s, requires: klass.requires.map(&:to_s),
                 description: klass.description, state: reason ? "unavailable" : record&.state || "off",
                 message: reason || record&.last_error)
      end
    end

    # Queues the task +kind+ (one of WarpEngine::LocalTask::KINDS)
    # on +target+ and returns it. Raises ArgumentError for an unknown
    # provider, WarpEngine::Local::Error while the providers are unavailable.
    def queue(kind, target)
      raise Local::Error, Local.unavailable_reason unless Local.available?
      raise ArgumentError, "no local provider #{target}" if kind != "local_ci" && Local::Providers.find(target).nil?

      task = LocalTask.create!(kind: kind, target: target.to_s)
      LocalTaskJob.perform_later(task.id)
      task
    end

    # Runs +task+: marks it running, does its work, then succeeded with
    # its result, or failed with the error. Returns the task.
    def run(task)
      task.update!(state: "running")
      result = case task.kind
      when "enable" then enable(task.target, task) && {}
      when "disable" then disable(task.target, task) && {}
      when "remove", "purge" then remove(task.target, task, purge: task.kind == "purge") && {}
      when "local_ci" then LocalCiService.new(providers: self).setup(task)
      end
      task.update!(state: "succeeded", result: result)
      task
    rescue StandardError => e
      task.step!("failed: #{e.message}")
      task.update!(state: "failed", error: e.message.truncate(2000))
      task
    end

    # Starts the provider +key+ (and what its roles need) and sets it up,
    # logging on +task+. Returns its WarpEngine::LocalProvider. Raises
    # WarpEngine::Local::Error (the record says why, +failed+).
    def enable(key, task)
      klass = Local::Providers.find(key) or raise ArgumentError, "no local provider #{key}"
      klass.requires.each { |role| ensure_role(role, task) }
      record = LocalProvider.for(key)
      record.mark!("starting")
      start(record.provider, task)
      record.mark!("ready")
      task.step!("#{klass.label} is ready")
      record
    rescue StandardError => e
      record&.mark!("failed", e.message)
      raise
    end

    # Returns the provider of +role+ after enabling it again (the one that
    # is on, else the first registered for the role): every step is
    # idempotent, and a container made from an older spec is replaced.
    def ensure_role(role, task)
      key = LocalProvider.where(role: role.to_s).where.not(state: "off").pick(:key) || Local::Providers.for_role(role).first&.key
      raise Local::Error, "no local provider plays #{role}" if key.nil?

      enable(key, task).provider
    end

    # Stops the provider +key+, after the ones that need its role. Its data stays.
    def disable(key, task)
      klass = Local::Providers.find(key) or raise ArgumentError, "no local provider #{key}"
      dependents(klass).each { |dependent| disable(dependent.key, task) }
      record = LocalProvider.find_by(key: key)
      return nil unless record

      record.provider.containers.reverse_each do |spec|
        task.step!("stop #{spec.name}")
        Local.runtime.stop(spec.name)
      end
      record.mark!("stopped")
    end

    # Removes the provider +key+'s containers (after the ones that need it);
    # with +purge+ its volumes and stored secrets too.
    def remove(key, task, purge: false)
      klass = Local::Providers.find(key) or raise ArgumentError, "no local provider #{key}"
      dependents(klass).each { |dependent| remove(dependent.key, task, purge: purge) }
      record = LocalProvider.find_by(key: key)
      return nil unless record

      provider = record.provider
      provider.containers.reverse_each do |spec|
        task.step!("remove #{spec.name}")
        Local.runtime.remove(spec.name)
      end
      return record.mark!("off") unless purge

      provider.volumes.each do |volume|
        task.step!("remove the volume #{volume}")
        Local.runtime.remove_volume(volume)
      end
      record.destroy!
    end

    private

    def dependents(klass)
      on = LocalProvider.where.not(state: %w[off]).pluck(:key)
      Local::Providers.classes.select { |other| other.requires.map(&:to_s).include?(klass.role.to_s) && on.include?(other.key) }
    end

    def start(provider, task)
      runtime = Local.runtime
      runtime.ensure_network(Local.config.network)
      provider.prepare(task)
      provider.containers.each do |spec|
        task.step!("pull #{spec.image}")
        runtime.pull(spec.image)
        task.step!("start #{spec.name}")
        runtime.run(spec, network: Local.config.network)
      end
      wait_until_healthy(provider, task)
      provider.bootstrap(task)
    end

    def wait_until_healthy(provider, task)
      task.step!("wait for #{provider.class.label}")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SECONDS
      until provider.healthy?
        raise Local::Error, "#{provider.class.label} did not answer in #{WAIT_SECONDS}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 2
      end
    end
  end
end
