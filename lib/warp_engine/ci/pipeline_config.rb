require "erb"
require "pathname"
require "yaml"

module WarpEngine
  module CI
    class PipelineConfig
      PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/
      OPTION_FORMAT = /\A[A-Za-z0-9_.-]{1,64}\z/

      BUILT_KINDS = {
        "tic80"      => %w[cartridge source html docs win_x64 linux_x64 mac_x64],
        "ebitengine" => %w[html win_x86 win_x64 linux_x64 linux_arm64],
        "godot"      => %w[html win_x86 win_x64 linux_x64 mac_universal],
        "love"       => %w[html win_x64 linux_x64 mac_universal],
        "bevy"       => %w[html win_x64 linux_x64 linux_arm64],
        "c64"        => %w[cartridge html win_x64 linux_x64 mac_arm64],
        "plus4"      => %w[cartridge html win_x64 linux_x64 mac_arm64],
        "phaser"     => %w[html],
        "dos"        => %w[cartridge win_x86]
      }.freeze

      RELEASE_STEPS = %w[upload artifact publish release store].freeze
      RELEASE_RULES = %w[push tag].freeze
      TAG_ONLY = %w[dos].freeze

      def self.adapter = raise(NotImplementedError)

      def self.templates_dir = raise(NotImplementedError)

      def initialize(platforms: {})
        @platforms = platforms.to_h { |key, spec| [ key.to_s, spec.to_h.symbolize_keys ] }
      end

      attr_reader :platforms

      def render(platform:, name:, update_server:, options: {})
        platform = platform.to_s
        return nil unless platform.match?(PLATFORM_FORMAT)

        spec = @platforms[platform]
        return nil if spec.nil?

        path = template_path(platform)
        return nil unless path&.exist?

        template = path.read
        if spec[:forge_release] && !template.include?("forge_release")
          Rails.logger.warn("[WarpEngine::CI] forge_release is on for #{platform}, but its pipeline has no release step")
        end

        options = clean_options(options)
        config = ERB.new(template, trim_mode: "-").result_with_hash(
          name:             name.to_s,
          update_server:    update_server.to_s,
          builder:          spec[:builder],
          exporter:         spec[:exporter],
          tools:            spec[:tools],
          web_shell:        spec[:web_shell],
          bundle_id_prefix: spec[:bundle_id_prefix] || "org.warpengine",
          forge_release:    spec[:forge_release] ? true : false,
          store:            spec[:store]&.to_h&.symbolize_keys,
          options:          options
        )
        return config if TAG_ONLY.include?(platform) || release_rule(platform, options) == "push"

        restrict_release_to_tags(config)
      end

      def release_rule(platform, options)
        return "tag" if TAG_ONLY.include?(platform.to_s)

        RELEASE_RULES.include?(options["release"]) ? options["release"] : "push"
      end

      def clean_options(options)
        options.to_h.each_with_object({}) do |(key, value), clean|
          key = key.to_s
          next if %w[platform name].include?(key)
          next unless key.match?(OPTION_FORMAT) && value.to_s.match?(OPTION_FORMAT)

          clean[key] = value.to_s
        end
      end

      def built_kinds(platform)
        platform = platform.to_s
        return nil unless @platforms.key?(platform)

        WarpEngine::Platform.registration(platform)&.built_kinds.presence || BUILT_KINDS[platform]
      end

      private

      def template_path(platform)
        registered = WarpEngine::Platform.registration(platform)&.templates&.dig(self.class.adapter)
        return registered if registered

        self.class.templates_dir.join(platform, "pipeline.yaml.erb")
      end

      def restrict_release_to_tags(config)
        document = YAML.safe_load(config)
        return config unless document.is_a?(Hash)

        tag_only(document)
        YAML.dump(document)
      end
    end
  end
end
