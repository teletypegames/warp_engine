module WarpEngine
  # Checks a publish before the CI runs it, writing nothing: what an editor
  # extension asks while the developer works, so that the problems a publish
  # would hit show up before the push.
  class PublishCheckService
    # One problem: the +field+ it is about (a metadata key, +version+ or
    # +kinds+), the +message+ and its +level+ (+error+: the publish would fail
    # or lose data; +warning+: it would succeed, but not as meant).
    Problem = ::Data.define(:field, :message, :level) do
      # Returns the problem as a Hash with String keys.
      def to_h = { "field" => field, "message" => message, "level" => level }
    end

    # Checks a publish of the platform +platform+.
    #
    # [platform] the platform name
    # [metadata] the metadata a publish would read (a Hash; +web+ included)
    # [version]  the version the pipeline would publish, or +nil+
    # [kinds]    the asset kinds the build would upload, or +nil+ to skip that check
    # [owner]    the token owner publishing (a record), or +nil+
    #
    # Returns the Problem list, empty when the publish would go through.
    def check(platform:, metadata:, version: nil, kinds: nil, owner: nil)
      found = WarpEngine::Platform.find(platform)
      return [ Problem.new(field: "platform", message: "#{platform} is not a platform", level: "error") ] if found.nil?

      metadata = metadata.to_h.deep_stringify_keys
      problems = metadata_problems(found, metadata)
      problems += version_problems(metadata["name"], version)
      problems += ownership_problems(metadata["name"], owner)
      problems += web_problems(found, metadata["web"])
      problems += kind_problems(found, kinds) unless kinds.nil?
      problems
    end

    private

    def metadata_problems(platform, metadata)
      problems = %w[name title].filter_map do |key|
        Problem.new(field: key, message: "#{key} is missing", level: "error") if metadata[key].blank?
      end
      unknown = metadata.keys - Publish::MetadataReader::KEYS.map(&:to_s) - %w[version]
      problems += unknown.map { |key| Problem.new(field: key, message: "#{key} is not read by a publish", level: "warning") }
      problems + shelf_name_problems(platform, metadata["name"], metadata["shelf_name"])
    end

    def shelf_name_problems(platform, name, shelf_name)
      return [] if shelf_name.blank?

      normalized = shelf_name.to_s.strip.upcase
      return [ Problem.new(field: "shelf_name", message: "may only have A-Z, 0-9 and -", level: "error") ] unless normalized.match?(Names::PATTERN)
      return [ Problem.new(field: "shelf_name", message: "is longer than 32 characters", level: "error") ] if normalized.length > 32

      taken = WarpEngine::Software.kept.where(platform: platform.name, shelf_name: normalized).where.not(name: name).exists?
      taken ? [ Problem.new(field: "shelf_name", message: "#{normalized} is taken on the #{platform.label} shelf", level: "error") ] : []
    end

    def version_problems(name, version)
      return [] if version.blank? || name.blank?

      reason = WarpEngine::PublishService.new.stale_reason(name, version)
      reason ? [ Problem.new(field: "version", message: reason, level: "error") ] : []
    end

    def ownership_problems(name, owner)
      return [] if owner.nil? || name.blank? || !WarpEngine.config.enforce_software_ownership

      software = WarpEngine::Software.kept.find_by(name: name)
      return [] if software.nil? || software.owner_id.nil?
      return [] if software.owner_type == owner.class.name && software.owner_id == owner.id

      [ Problem.new(field: "name", message: "#{name} belongs to someone else", level: "error") ]
    end

    def web_problems(platform, web)
      return [] if web.nil?
      return [ Problem.new(field: "web", message: "must be an object", level: "error") ] unless web.is_a?(Hash)
      return [] if web["enabled"] == false

      binding = platform.web_binding(web["runtime"])
      if binding.nil?
        message = web["runtime"].present? ? "#{platform.label} has no web runtime #{web['runtime']}" : "#{platform.label} plays on the web from its html asset only"
        return web["runtime"].present? ? [ Problem.new(field: "web", message: message, level: "error") ] : []
      end

      params = web["params"].is_a?(Hash) ? web["params"] : {}
      definition = binding.runtime_object&.definition
      return [] if definition.nil?

      (params.keys.map(&:to_sym) - definition.params.keys).map do |key|
        Problem.new(field: "web", message: "#{binding.runtime} takes no parameter #{key}", level: "warning")
      end
    end

    def kind_problems(platform, kinds)
      missing = platform.required_kinds - Array(kinds).map(&:to_s)
      problems = missing.map { |kind| Problem.new(field: "kinds", message: "#{kind} is required and not built", level: "error") }
      unknown = Array(kinds).map(&:to_s) - platform.expected_kinds
      problems + unknown.map { |kind| Problem.new(field: "kinds", message: "#{platform.label} does not publish #{kind}", level: "warning") }
    end
  end
end
