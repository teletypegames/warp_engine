require "erb"
require "pathname"

module WarpEngine
  module CI
    module Woodpecker
      class PipelineConfig
        PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/

        BUILT_KINDS = {
          "tic80"      => %w[cartridge source html docs win_x64 linux_x64 mac_x64],
          "ebitengine" => %w[html win_x86 win_x64 linux_x64 linux_arm64],
          "godot"      => %w[html win_x86 win_x64 linux_x64 mac_universal],
          "love"       => %w[html win_x64 linux_x64 mac_universal],
          "bevy"       => %w[html win_x64 linux_x64 linux_arm64],
          "c64"        => %w[cartridge html win_x64 linux_x64 mac_universal],
          "plus4"      => %w[cartridge html win_x64 linux_x64 mac_universal],
          "phaser"     => %w[html]
        }.freeze

        def initialize(platforms: {})
          @platforms = platforms.to_h { |key, spec| [ key.to_s, spec.to_h.symbolize_keys ] }
        end

        def platforms
          @platforms
        end

        def render(platform:, name:, update_server:)
          platform = platform.to_s
          return nil unless platform.match?(PLATFORM_FORMAT)

          spec = @platforms[platform]
          return nil if spec.nil?

          path = self.class.templates_dir.join(platform, "pipeline.yaml.erb")
          return nil unless path.exist?

          ERB.new(path.read, trim_mode: "-").result_with_hash(
            name:          name.to_s,
            update_server: update_server.to_s,
            builder:       spec[:builder],
            exporter:      spec[:exporter]
          )
        end

        def built_kinds(platform)
          platform = platform.to_s
          return nil unless @platforms.key?(platform)

          BUILT_KINDS[platform]
        end

        def self.templates_dir
          Pathname.new(__dir__).join("platforms")
        end
      end
    end
  end
end
