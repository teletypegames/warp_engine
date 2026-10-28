require "erb"
require "pathname"
require "yaml"

module WarpEngine
  module CI
    # Renders the per-platform pipeline a CI adapter serves for a marker config
    # (<tt>platform: godot</tt>): the platform's ERB template, then the steps
    # every pipeline shares added around it (+version+ first, +tag+ after a push
    # build when releases follow tags, the forge +release+ when the platform asks
    # for it) and the events the pipeline runs on.
    #
    # This is the provider-neutral base; CI::Woodpecker::PipelineConfig and
    # CI::Gitlab::PipelineConfig supply the template directory and the
    # provider's YAML dialect for the shared steps.
    class PipelineConfig
      # The pattern a platform name must match before its template is looked up.
      PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/
      # The pattern both the key and the value of a marker option must match to reach the template.
      OPTION_FORMAT = /\A[A-Za-z0-9_.-]{1,64}\z/

      # The release file kinds the bundled template of each built-in platform produces, by platform name.
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

      # The step (job) names that release a build and run on tags only when releases follow tags.
      RELEASE_STEPS = %w[package upload publish release].freeze
      # The accepted values of the +release+ marker option.
      RELEASE_RULES = %w[push tag].freeze

      # The shell command that prints the +version+ of the repository's metadata.json.
      METADATA_VERSION = <<~'SH'.chomp.freeze
        sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1
      SH
      # Shell commands that print the source version of a platform whose version is not in
      # metadata.json, by platform name.
      VERSION_SOURCES = {
        "tic80" => <<~'SH'.chomp.freeze
          sed -n 's/^-- version: //p' inc/meta/meta.header.lua 2>/dev/null | head -n 1 | tr -d '[:space:]'
        SH
      }.freeze

      # Returns the adapter key (+:woodpecker+, +:gitlab+) a platform registration's
      # +templates+ Hash is looked up by. Raises NotImplementedError in the base class.
      def self.adapter = raise(NotImplementedError)

      # Returns the Pathname holding the bundled <tt><platform>/pipeline.yaml.erb</tt>
      # templates. Raises NotImplementedError in the base class.
      def self.templates_dir = raise(NotImplementedError)

      # Creates the renderer.
      #
      # [platforms] the platforms the adapter builds, a Hash of platform name to its
      #             settings (+builder+, +exporter+, +tools+, +web_shell+,
      #             +bundle_id_prefix+, +forge_release+)
      def initialize(platforms: {})
        @platforms = platforms.to_h { |key, spec| [ key.to_s, spec.to_h.symbolize_keys ] }
      end

      # The configured platforms: a Hash of String platform name to a Hash of Symbol-keyed settings.
      attr_reader :platforms

      # Renders the pipeline of +platform+ for a repository.
      #
      # [platform]      the platform name from the marker
      # [name]          the software name the release is published under
      # [update_server] the base URL of the catalog the pipeline uploads to
      # [options]       the marker's other keys; invalid ones are dropped (#clean_options)
      #
      # Returns the pipeline YAML String, or +nil+ when the platform name is
      # malformed, not configured, or has no template. A template that does not
      # render to a YAML mapping is returned as rendered, without the shared steps.
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
        if release_rule(platform, options) == "tag"
          tag_only(document)
          add_tag_step(document, image: spec[:tools], script: tag_script)
        end
        add_release_step(document, image: spec[:tools], script: release_script(name.to_s)) if spec[:forge_release]
        limit_events(document)
        YAML.dump(document)
      end

      # Returns which builds release +platform+: <tt>"tag"</tt> when the platform's
      # service demands it, otherwise the +release+ option when it is one of
      # RELEASE_RULES, and <tt>"tag"</tt> by default.
      def release_rule(platform, options)
        return "tag" if WarpEngine::Platform.find(platform)&.service_class&.release_rule == "tag"

        chosen = options.to_h.transform_keys(&:to_s)["release"]
        RELEASE_RULES.include?(chosen) ? chosen : "tag"
      end

      # Returns the marker +options+ as a Hash of Strings, without +platform+ and
      # +name+ and without any pair whose key or value does not match OPTION_FORMAT.
      def clean_options(options)
        options.to_h.each_with_object({}) do |(key, value), clean|
          key = key.to_s
          next if %w[platform name].include?(key)
          next unless key.match?(OPTION_FORMAT) && value.to_s.match?(OPTION_FORMAT)

          clean[key] = value.to_s
        end
      end

      # Returns the Array of release file kinds the pipeline of +platform+ builds:
      # the platform registration's +built_kinds+, else BUILT_KINDS. Returns +nil+
      # when the platform is not configured for this adapter.
      def built_kinds(platform)
        platform = platform.to_s
        return nil unless @platforms.key?(platform)

        WarpEngine::Platform.registration(platform)&.built_kinds.presence || BUILT_KINDS[platform]
      end

      # Returns the shell command that prints the source version of +platform+: the
      # registration's +version_source+, else VERSION_SOURCES, else METADATA_VERSION.
      def version_source(platform)
        WarpEngine::Platform.registration(platform)&.version_source.presence ||
          VERSION_SOURCES.fetch(platform.to_s, METADATA_VERSION)
      end

      # Returns the shell script of the +version+ step. It checks that a version tag
      # matches the source version (failing the build otherwise), falls back to
      # <tt>dev-<sha></tt> without any version, marks builds off the default branch
      # or from a <tt>dev-</tt> tag as <tt>dev-<version>-<branch></tt>, and writes the
      # result to +.version+.
      def version_script(platform)
        <<~SH
          SOURCE_VERSION=$(#{version_source(platform)})
          TAG="${CI_COMMIT_TAG:-}"
          TAG_VERSION=""
          DEV_TAG=""
          BRANCH=$(printf '%s' "#{branch_expression}" | tr '/' '-')
          case "$TAG" in
            v[0-9]*|[0-9]*) TAG_VERSION=$(printf '%s' "$TAG" | sed 's/^v//') ;;
            dev-*) DEV_TAG=yes; BRANCH=$(printf '%s' "$TAG" | sed 's/^dev-//') ;;
          esac
          if [ -n "$TAG_VERSION" ] && [ -n "$SOURCE_VERSION" ] && [ "$TAG_VERSION" != "$SOURCE_VERSION" ]; then
            echo "ERROR: the tag $TAG does not match the version $SOURCE_VERSION of the source!"
            exit 1
          fi
          VERSION="$SOURCE_VERSION"
          if [ -z "$VERSION" ]; then VERSION="$TAG_VERSION"; fi
          if [ -z "$VERSION" ]; then
            SHA="${CI_COMMIT_SHA:-unknown}"
            VERSION="dev-$(printf '%.7s' "$SHA")"
            echo "No version in the source and no version tag: this build is $VERSION"
          fi
          DEFAULT_BRANCH=$(printf '%s' "#{default_branch_expression}" | tr '/' '-')
          ON_DEFAULT=""
          if [ -n "$DEFAULT_BRANCH" ]; then
            if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then ON_DEFAULT=yes; fi
          else
            case "$BRANCH" in main|master) ON_DEFAULT=yes ;; esac
          fi
          if [ -n "$DEV_TAG" ] || { [ -z "$TAG" ] && [ -n "$BRANCH" ] && [ -z "$ON_DEFAULT" ]; }; then
            case "$VERSION" in dev-*) ;; *) VERSION="dev-$VERSION-$BRANCH" ;; esac
          fi
          echo "VERSION is: $VERSION"
          echo "$VERSION" > .version
        SH
      end

      # Returns the shell script of the +tag+ step, run after a push build: a new
      # version gets its <tt>v<version></tt> tag on the forge, whose pipeline
      # releases it; a version already tagged releases nothing. A dev build moves
      # the branch's <tt>dev-<branch></tt> tag onto its commit, so the dev release
      # follows the branch.
      def tag_script
        <<~SH
          set -eu
          VERSION=$(cat .version)
          BRANCH=$(printf '%s' "#{branch_expression}" | tr '/' '-')
          case "$VERSION" in
            dev-*) TAG="dev-$BRANCH"; MOVE=yes ;;
            *) TAG="v$VERSION"; MOVE="" ;;
          esac
          if [ "$TAG" = "dev-" ]; then echo "No branch to name the dev tag after: nothing to tag"; exit 0; fi
          #{forge_tag_setup.strip}
          CURRENT=$(#{forge_tag_lookup} 2>/dev/null || true)
          if [ -n "$CURRENT" ]; then
            if [ -z "$MOVE" ]; then echo "==> $TAG is tagged already: this build releases nothing"; exit 0; fi
            if [ "$CURRENT" = "$CI_COMMIT_SHA" ]; then echo "==> $TAG is on this commit already"; exit 0; fi
            echo "==> Moving $TAG to $CI_COMMIT_SHA"
            #{forge_tag_delete} >/dev/null
          else
            echo "==> Tagging $CI_COMMIT_SHA as $TAG"
          fi
          #{forge_tag_create} >/dev/null
        SH
      end

      # Returns the shell snippet that sets +FILES+ (the files listed in
      # +.release-assets+, else the <tt><name>-$VERSION.*</tt> and
      # <tt><name>-$VERSION-*</tt> files without metadata), +TITLE+ (from
      # metadata.json, else +name+) and +NOTES+ (RELEASE_NOTES.md) for a release
      # script. The snippet exits with an error when there is nothing to attach.
      def release_files_script(name)
        <<~SH
          if [ -f .release-assets ]; then
            FILES=$(cat .release-assets)
          else
            FILES=$(find . -maxdepth 1 -type f \\( -name "#{name}-$VERSION.*" -o -name "#{name}-$VERSION-*" \\) ! -name '*.metadata.json' | sed 's|^\\./||' | sort)
          fi
          [ -n "$FILES" ] || { echo "ERROR: nothing to attach to the release"; exit 1; }
          TITLE=$(jq -r '.title // .name // empty' metadata.json 2>/dev/null || true)
          if [ -z "$TITLE" ]; then TITLE="#{name}"; fi
          NOTES=""
          if [ -f RELEASE_NOTES.md ]; then NOTES=$(cat RELEASE_NOTES.md); fi
        SH
      end

      private

      def branch_expression = raise(NotImplementedError)

      def default_branch_expression = raise(NotImplementedError)

      def add_tag_step(document, image:, script:) = raise(NotImplementedError)

      def limit_events(_document) = nil

      def forge_tag_setup = raise(NotImplementedError)

      def forge_tag_lookup = raise(NotImplementedError)

      def forge_tag_delete = raise(NotImplementedError)

      def forge_tag_create = raise(NotImplementedError)

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
