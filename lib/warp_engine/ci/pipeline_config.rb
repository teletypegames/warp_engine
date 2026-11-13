require "erb"
require "pathname"
require "yaml"
require "warp_engine/ci/step"

module WarpEngine
  module CI
    # Renders the per-platform pipeline a CI adapter serves for a marker config
    # (<tt>platform: godot</tt>). A pipeline is a list of CI::Step objects:
    #
    # 1. +version+, which writes <tt>.version</tt> (<tt>scripts/version.sh</tt>);
    # 2. the platform's own steps, from its CI-neutral template
    #    (<tt>lib/warp_engine/ci/platforms/<template>.yaml.erb</tt>, or the
    #    host's, see WarpEngine::Platform::Builder#ci);
    # 3. +upload+ and +publish+, generated from the platform's kinds
    #    (<tt>scripts/upload.sh</tt>, <tt>scripts/publish.sh</tt>): the kinds
    #    the pipeline always builds (and the metadata) must be there, every
    #    other kind the platform accepts is uploaded when the build made it;
    # 4. +tag+ after a push build when releases follow tags, and the forge
    #    +release+ when the host asks for it.
    #
    # The adapter's renderer then writes the steps in its YAML dialect. This is
    # the provider-neutral base; CI::Woodpecker::PipelineConfig and
    # CI::Gitlab::PipelineConfig supply the renderer, the branch variables, the
    # forge scripts and secrets.
    #
    # A CI-neutral template renders to a mapping with +steps+ (each +name+,
    # +image+, +commands+, optionally +environment+, +artifacts+ and +pull+) and
    # an optional +upload+ (+prepare+: shell lines run before the upload,
    # +packages+: what the upload needs from apk without a tools image).
    class PipelineConfig
      # The pattern a platform name must match before its template is looked up.
      PLATFORM_FORMAT = /\A[a-z0-9_-]+\z/
      # The pattern both the key and the value of a marker option must match to reach the template.
      OPTION_FORMAT = /\A[A-Za-z0-9_.-]{1,64}\z/
      # The directory of the builtin CI-neutral platform templates.
      TEMPLATES_DIR = Pathname.new(__dir__).join("platforms")
      # The step (job) names that release a build and run on tags only when releases follow tags.
      RELEASE_STEPS = %w[package upload publish release].freeze
      # The accepted values of the +release+ marker option.
      RELEASE_RULES = %w[push tag].freeze
      # The shell command that prints the +version+ of the repository's metadata.json.
      METADATA_VERSION = <<~'SH'.chomp.freeze
        sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1
      SH

      # Returns the adapter key (+:woodpecker+, +:gitlab+) a legacy platform
      # registration's +templates+ Hash is looked up by. Raises
      # NotImplementedError in the base class.
      def self.adapter = raise(NotImplementedError)

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
      # malformed, not configured, or has no template. A legacy template that
      # does not render to a YAML mapping is returned as rendered, without the
      # shared steps.
      def render(platform:, name:, update_server:, options: {})
        platform_name = platform.to_s
        return nil unless platform_name.match?(PLATFORM_FORMAT)

        spec = @platforms[platform_name]
        found = WarpEngine::Platform.find(platform_name)
        return nil if spec.nil? || found.nil?

        options = clean_options(options)
        body = found.legacy? ? legacy_steps(found, spec, name, update_server, options) : platform_steps(found, spec, name, update_server, options)
        return body unless body.is_a?(Array)

        steps, extras = body
        steps = [ version_step(platform_name, spec) ] + steps
        if release_rule(platform_name, options) == "tag"
          steps = steps.map { |step| RELEASE_STEPS.include?(step.name) ? step.with(on: :tag) : step }
          steps << tag_step(spec)
        end
        steps << release_step(name.to_s, spec) if spec[:forge_release]
        YAML.dump(renderer.render(steps, extras))
      end

      # Returns which builds release +platform+: <tt>"tag"</tt> when the platform
      # demands it (WarpEngine::Platform#release_rule), otherwise the +release+
      # option when it is one of RELEASE_RULES, and <tt>"tag"</tt> by default.
      def release_rule(platform, options)
        return "tag" if WarpEngine::Platform.find(platform)&.release_rule == "tag"

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

      # Returns the release file kinds the pipeline of +platform+ builds
      # (WarpEngine::Platform#built_kinds), or +nil+ when the platform is not
      # configured for this adapter.
      def built_kinds(platform)
        platform = platform.to_s
        return nil unless @platforms.key?(platform)

        WarpEngine::Platform.find(platform)&.built_kinds
      end

      # Returns the shell command that prints the source version of +platform+:
      # WarpEngine::Platform#version_source, else METADATA_VERSION.
      def version_source(platform)
        WarpEngine::Platform.find(platform)&.version_source.presence || METADATA_VERSION
      end

      # Returns the shell script of the +version+ step (<tt>scripts/version.sh</tt>
      # after the source version and the adapter's branch variables). It checks
      # that a version tag matches the source version (failing the build
      # otherwise), falls back to <tt>dev-<sha></tt> without any version, marks
      # builds off the default branch or from a <tt>dev-</tt> tag as
      # <tt>dev-<version>-<branch></tt>, and writes the result to +.version+.
      def version_script(platform)
        "SOURCE_VERSION=$(#{version_source(platform)})\n" + branch_prelude + Scripts.read("version")
      end

      # Returns the shell script of the +tag+ step, run after a push build
      # (<tt>scripts/tag.sh</tt> with the adapter's forge functions): a new
      # version gets its <tt>v<version></tt> tag on the forge, whose pipeline
      # releases it; a version already tagged releases nothing. A dev build moves
      # the branch's <tt>dev-<branch></tt> tag onto its commit, so the dev release
      # follows the branch.
      def tag_script
        branch_prelude + Scripts.read("forge", dir: scripts_dir) + Scripts.read("tag")
      end

      # Returns the shell script of the forge +release+ step of the software
      # +name+: <tt>scripts/release_files.sh</tt> (which files, title and notes)
      # and the adapter's <tt>scripts/release.sh</tt>.
      def release_script(name)
        Scripts.assign(NAME: name) + Scripts.read("release_files") + Scripts.read("release", dir: scripts_dir)
      end

      private

      def renderer = raise(NotImplementedError)

      def scripts_dir = raise(NotImplementedError)

      def branch_expression = raise(NotImplementedError)

      def default_branch_expression = raise(NotImplementedError)

      def forge_secrets = {}

      def branch_prelude
        %(BRANCH_SOURCE="#{branch_expression}"\nDEFAULT_BRANCH_SOURCE="#{default_branch_expression}"\n)
      end

      def locals(platform, spec, name, update_server, options)
        { name:             name.to_s,
          update_server:    update_server.to_s,
          builder:          spec[:builder],
          exporter:         spec[:exporter],
          tools:            spec[:tools],
          web_shell:        spec[:web_shell],
          bundle_id_prefix: spec[:bundle_id_prefix] || "org.warpengine",
          options:          options }.merge(platform.definition.ci_variables.to_h.symbolize_keys)
      end

      def evaluate(path, locals)
        ERB.new(path.read, trim_mode: "-").result_with_hash(locals)
      end

      def platform_steps(platform, spec, name, update_server, options)
        template = platform.definition.ci_template.to_s
        path = Pathname.new(template).absolute? ? Pathname.new(template) : TEMPLATES_DIR.join("#{template}.yaml.erb")
        return nil unless path.file?

        document = YAML.safe_load(evaluate(path, locals(platform, spec, name, update_server, options)))
        steps = Array(document["steps"]).map { |step| Step.from_template(step) }
        upload = document["upload"].to_h
        [ steps + [ upload_step(platform, spec, name.to_s, update_server.to_s, upload),
                    publish_step(platform, spec, name.to_s, update_server.to_s) ], {} ]
      end

      def legacy_steps(platform, spec, name, update_server, options)
        path = platform.legacy_template(self.class.adapter)
        return nil unless path&.exist?

        config = evaluate(path, locals(platform, spec, name, update_server, options))
        document = YAML.safe_load(config)
        document.is_a?(Hash) ? renderer.parse(document) : config
      end

      def helper_commands(spec, packages, script)
        (spec[:tools] ? [] : [ "apk add --no-cache #{packages.join(' ')}" ]) + [ script ]
      end

      def version_step(platform, spec)
        Step.new(name: "version", image: spec[:tools] || "alpine", commands: [ version_script(platform) ], artifacts: [ ".version" ])
      end

      def upload_step(platform, spec, name, update_server, upload)
        specs = platform.kind_specs
        metadata = platform.definition.metadata.to_s == "json"
        always = specs.select { |spec| spec.built && spec.always }.map(&:upload_suffix) + (metadata ? [ ".metadata.json" ] : [])
        maybe = specs.reject { |spec| spec.built && spec.always }.map(&:upload_suffix)
        inputs = Scripts.assign(NAME: name, ALWAYS: always.join(" "), MAYBE: maybe.join(" "), METADATA: metadata ? "yes" : "")
        script = inputs + "VERSION=$(cat .version)\n" + upload["prepare"].to_s + Scripts.read("upload")
        Step.new(name: "upload", image: spec[:tools] || "alpine", environment: { "UPDATE_SERVER" => update_server },
                 secrets: { "UPDATE_SECRET" => "application_token" },
                 commands: helper_commands(spec, [ "curl" ] + Array(upload["packages"]), script))
      end

      def publish_step(platform, spec, name, update_server)
        script = Scripts.assign(NAME: name, PLATFORM: platform.name) + Scripts.read("publish")
        Step.new(name: "publish", image: spec[:tools] || "alpine", environment: { "UPDATE_SERVER" => update_server },
                 secrets: { "UPDATE_SECRET" => "application_token" }, commands: helper_commands(spec, %w[curl], script))
      end

      def tag_step(spec)
        Step.new(name: "tag", image: spec[:tools] || "alpine", secrets: forge_secrets, on: :branch,
                 commands: helper_commands(spec, %w[curl], tag_script))
      end

      def release_step(name, spec)
        Step.new(name: "release", image: spec[:tools] || "alpine", secrets: forge_secrets, on: :tag,
                 commands: helper_commands(spec, %w[curl jq], release_script(name)))
      end
    end
  end
end
