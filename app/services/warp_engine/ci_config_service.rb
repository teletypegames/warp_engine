require "erb"

module WarpEngine
  # A /build/config platform-template-jeinek renderelése: a pipeline-logika
  # a lib/warp_engine/ci_templates/<platform>.yaml.erb fájlokban él, a
  # platformonkénti builder image-eket a WarpEngine.config.ci_platforms adja.
  class CiConfigService
    PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/

    # A renderelt pipeline YAML, vagy nil, ha a platform nem kiszolgált.
    def render(platform:, name:, update_server:)
      platform = platform.to_s
      return nil unless platform.match?(PLATFORM_FORMAT)

      spec = platform_spec(platform)
      return nil if spec.nil?

      path = templates_dir.join("#{platform}.yaml.erb")
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
      WarpEngine::Engine.root.join("lib", "warp_engine", "ci_templates")
    end
  end
end
