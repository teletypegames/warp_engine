module WarpEngine
  # Per-request memory of the engine (ActiveSupport::CurrentAttributes, reset
  # by Rails around every request and job): the installed runtime versions
  # and the fork counts, read once however many releases and softwares a
  # catalog page serializes.
  class Current < ActiveSupport::CurrentAttributes
    # The kept WarpEngine::RuntimeVersion records with their components, or
    # +nil+ until #runtime_versions first loads them.
    attribute :installed_runtime_versions

    # The fork counts as a Hash of software name to count, or +nil+ until
    # #fork_count first loads them.
    attribute :fork_counts

    # Returns how many forks of +software+ are listed: the kept softwares of
    # this engine that name it as their parent and its visible
    # WarpEngine::SoftwareFork records.
    def fork_count(software)
      self.fork_counts ||= load_fork_counts
      fork_counts.fetch(software.name, 0)
    end

    # Returns the kept WarpEngine::RuntimeVersion records, components loaded.
    def runtime_versions
      self.installed_runtime_versions ||= WarpEngine::RuntimeVersion.kept.includes(:runtime_components).to_a
    end

    # Returns the kept WarpEngine::RuntimeVersion with the id +id+, or +nil+.
    def runtime_version(id) = runtime_versions.find { |version| version.id == id }

    # Returns the WarpEngine::RuntimeVersion new releases of the runtime
    # +runtime+ (a WarpEngine::Runtime) get, as WarpEngine::Runtime#current_version
    # finds it, or +nil+.
    def current_runtime_version(runtime)
      own = runtime_versions.select { |version| version.name == runtime.name }
      chosen = runtime.chosen_version
      chosen ? own.find { |version| version.version == chosen } : own.max_by { |version| [ version.created_at, version.id ] }
    end

    private

    def load_fork_counts
      counts = Hash.new(0)
      own = WarpEngine::Forks.engine_url
      if own
        WarpEngine::Software.kept.where(fork_of_engine: own).group(:fork_of_name).count.each { |name, count| counts[name] += count }
      end
      WarpEngine::SoftwareFork.visible.joins(:software).group("softwares.name").count.each { |name, count| counts[name] += count }
      counts
    end
  end
end
