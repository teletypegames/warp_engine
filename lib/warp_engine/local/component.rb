module WarpEngine
  module Local
    # The base of a local component (WarpEngine::Local::Components): a
    # service this engine starts beside itself in containers and wires in.
    # A component class names itself (+key+, +label+, +role+ — one component
    # per role is on at a time —, the roles it +requires+); an instance works
    # on its WarpEngine::LocalComponent record:
    #
    # [prepare]       before its containers start (e.g. an OAuth app on the forge)
    # [containers]    its WarpEngine::Local::ContainerSpec list
    # [healthy?]      whether it answers
    # [bootstrap]     idempotent set-up once it answers (users, tokens)
    # [adapter]       the engine seam's adapter built from what it stored
    # [connect]       its part of setting a software up (WarpEngine::LocalCiService)
    # [credentials]   the generated sign-in, for a person
    #
    # Every step logs on the WarpEngine::LocalOperation it is given.
    class Component
      class << self
        # Returns the key, e.g. <tt>"gitea"</tt>.
        def key = raise(NotImplementedError, "#{name} must define self.key")

        # Returns the human name.
        def label = key.to_s.titleize

        # Returns the role, e.g. +:forge+ or +:ci+.
        def role = raise(NotImplementedError, "#{name} must define self.role")

        # Returns the roles that must be on first, by default none.
        def requires = []

        # Returns a sentence about what it is.
        def description = ""
      end

      # The WarpEngine::LocalComponent record.
      attr_reader :record

      # [record] the WarpEngine::LocalComponent of this component
      def initialize(record)
        @record = record
      end

      # Returns the local settings (WarpEngine::Local.config).
      def config = Local.config

      # Returns the container runtime (WarpEngine::Local.runtime).
      def runtime = Local.runtime

      # Returns the HTTP helper, with #rewrites.
      def http = @http ||= Http.new(rewrites: rewrites)

      # Returns the URL prefixes to fetch from elsewhere (see WarpEngine::Local::Http), by default none.
      def rewrites = {}

      # Runs before the containers start, by default nothing.
      def prepare(_operation) = nil

      # Returns the WarpEngine::Local::ContainerSpec list, by default none.
      def containers = []

      # Returns whether the component answers, by default whether every container runs.
      def healthy? = containers.all? { |spec| runtime.state(spec.name) == "running" }

      # Runs once the component answers, by default nothing.
      def bootstrap(_operation) = nil

      # Returns the engine seam's adapter, or +nil+ (the default).
      def adapter(_base = nil) = nil

      # Does the component's part of setting +software+ up, adding to the
      # +result+ Hash; by default nothing.
      def connect(_software, _operation, _result) = nil

      # Returns the generated sign-in, by default none.
      def credentials = {}

      # Returns the names of the volumes its containers keep data in.
      def volumes = containers.flat_map { |spec| spec.volumes.keys }

      # Returns a stored setting.
      def setting(name) = record.settings.to_h[name.to_s]

      # Returns a stored secret.
      def secret(name) = record.secrets[name.to_s]

      # Stores +settings+ and +secrets+ (Hashes) on the record, merged into what is there.
      def store!(settings: {}, secrets: {})
        record.settings = record.settings.to_h.merge(settings.stringify_keys)
        record.secrets = record.secrets.merge(secrets.stringify_keys)
        record.save!
      end
    end
  end
end
