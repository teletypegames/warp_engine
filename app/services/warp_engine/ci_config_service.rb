require "erb"

module WarpEngine

  class CiConfigService
    PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/

    def render(platform:, name:, update_server:)
      platform = platform.to_s
      return nil unless platform.match?(PLATFORM_FORMAT)

      spec = platform_spec(platform)
      return nil if spec.nil?

      path = templates_dir.join(platform, "pipeline.yaml.erb")
      return nil unless path.exist?

      ERB.new(path.read, trim_mode: "-").result_with_hash(
        name:          name.to_s,
        update_server: update_server.to_s,
        builder:       spec[:builder],
        exporter:      spec[:exporter]
      )
    end

    private

    def platform_spec(platform)
      spec = WarpEngine.config.ci_platforms.stringify_keys[platform]
      spec&.symbolize_keys
    end

    def templates_dir
      WarpEngine::Engine.root.join("app", "services", "warp_engine", "platforms")
    end
  end
end
