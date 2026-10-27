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

      RELEASE_STEPS = %w[package upload publish release].freeze
      RELEASE_RULES = %w[push tag].freeze

      METADATA_VERSION = <<~'SH'.chomp.freeze
        sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1
      SH
      VERSION_SOURCES = {
        "tic80" => <<~'SH'.chomp.freeze
          sed -n 's/^-- version: //p' inc/meta/meta.header.lua 2>/dev/null | head -n 1 | tr -d '[:space:]'
        SH
      }.freeze

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

        options = clean_options(options)
        config = ERB.new(path.read, trim_mode: "-").result_with_hash(
          name:             name.to_s,
          update_server:    update_server.to_s,
          builder:          spec[:builder],
          exporter:         spec[:exporter],
          tools:            spec[:tools],
          web_shell:        spec[:web_shell],
          bundle_id_prefix: spec[:bundle_id_prefix] || "org.warpengine",
          options:          options
        )

        document = YAML.safe_load(config)
        return config unless document.is_a?(Hash)

        add_version_step(document, image: spec[:tools], script: version_script(platform))
        add_release_step(document, image: spec[:tools], script: release_script(name.to_s)) if spec[:forge_release]
        tag_only(document) if release_rule(platform, options) == "tag"
        YAML.dump(document)
      end

      def release_rule(platform, options)
        return "tag" if WarpEngine::Platform.find(platform)&.service_class&.release_rule == "tag"

        chosen = options.to_h.transform_keys(&:to_s)["release"]
        RELEASE_RULES.include?(chosen) ? chosen : "push"
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

      def version_source(platform)
        WarpEngine::Platform.registration(platform)&.version_source.presence ||
          VERSION_SOURCES.fetch(platform.to_s, METADATA_VERSION)
      end

      def version_script(platform)
        <<~SH
          SOURCE_VERSION=$(#{version_source(platform)})
          TAG="${CI_COMMIT_TAG:-}"
          TAG_VERSION=""
          case "$TAG" in v[0-9]*|[0-9]*) TAG_VERSION="${TAG#v}" ;; esac
          if [ -n "$TAG_VERSION" ] && [ -n "$SOURCE_VERSION" ] && [ "$TAG_VERSION" != "$SOURCE_VERSION" ]; then
            echo "ERROR: the tag $TAG does not match the version $SOURCE_VERSION of the source!"
            exit 1
          fi
          VERSION="${SOURCE_VERSION:-$TAG_VERSION}"
          if [ -z "$VERSION" ]; then
            SHA="${CI_COMMIT_SHA:-unknown}"
            VERSION="dev-$(printf '%.7s' "$SHA")"
            echo "No version in the source and no version tag: this build is $VERSION"
          fi
          BRANCH=$(printf '%s' "#{branch_expression}" | tr '/' '-')
          if [ -z "$TAG" ] && [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
            case "$VERSION" in dev-*) ;; *) VERSION="dev-$VERSION-$BRANCH" ;; esac
          fi
          echo "VERSION is: $VERSION"
          echo "$VERSION" > .version
        SH
      end

      def release_files_script(name)
        <<~SH
          if [ -f .release-assets ]; then
            FILES=$(cat .release-assets)
          else
            FILES=$(find . -maxdepth 1 -type f \\( -name "#{name}-$VERSION.*" -o -name "#{name}-$VERSION-*" \\) ! -name '*.metadata.json' | sed 's|^\\./||' | sort)
          fi
          [ -n "$FILES" ] || { echo "ERROR: nothing to attach to the release"; exit 1; }
          TITLE=$(jq -r '.title // .name // empty' metadata.json 2>/dev/null || true)
          TITLE="${TITLE:-#{name}}"
          NOTES=""
          if [ -f RELEASE_NOTES.md ]; then NOTES=$(cat RELEASE_NOTES.md); fi
        SH
      end

      private

      def branch_expression = raise(NotImplementedError)

      def add_version_step(document, image:, script:) = raise(NotImplementedError)

      def add_release_step(document, image:, script:) = raise(NotImplementedError)

      def release_script(name) = raise(NotImplementedError)

      def tag_only(document) = raise(NotImplementedError)

      def template_path(platform)
        registered = WarpEngine::Platform.registration(platform)&.templates&.dig(self.class.adapter)
        return registered if registered

        self.class.templates_dir.join(platform, "pipeline.yaml.erb")
      end
    end
  end
end
