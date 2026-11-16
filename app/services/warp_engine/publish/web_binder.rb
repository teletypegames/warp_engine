module WarpEngine
  module Publish
    # Binds a release to the runtime it plays in on the web. The binding is
    # the one the release's metadata names (<tt>web.runtime</tt>, a binding
    # key of the platform) or the platform's default; the runtime version is
    # the one the new releases get (WarpEngine::Runtime#current_version), and
    # it must hold the components the binding needs. A release whose metadata
    # says <tt>web.enabled: false</tt>, whose platform has no binding, or whose
    # runtime is not installed is left unbound and plays (if at all) from its
    # +html+ asset.
    class WebBinder
      # [platform] the WarpEngine::Platform, or +nil+ (nothing is bound)
      def initialize(platform)
        @platform = platform
      end

      # Sets +runtime_version+, +web_binding+ and +web_options+ of +release+
      # from the metadata's +web+ section (+web+, a Hash or +nil+) and saves
      # it. Returns the WarpEngine::RuntimeVersion bound, or +nil+.
      def bind(release, web)
        web = web.is_a?(Hash) ? web.deep_stringify_keys : {}
        binding = choose(web)
        version = binding && available_version(binding)
        release.update!(runtime_version: version, web_binding: version && binding.key,
                        web_options: web.slice("enabled", "params", "start").presence)
        version
      end

      # Returns the installed WarpEngine::RuntimeVersion of the runtime of
      # +binding+ that the new releases get, when it holds every component
      # the binding names; +nil+ otherwise.
      def available_version(binding)
        runtime = binding.runtime_object
        return nil if runtime.nil? || !binding.valid?

        version = runtime.current_version
        version if version && WebBinder.components_installed?(version, binding)
      end

      # Returns +true+ when +version+ (a WarpEngine::RuntimeVersion) holds
      # every component the parameters of +binding+ name.
      def self.components_installed?(version, binding)
        definition = binding.runtime_object&.definition
        return false if definition.nil?

        definition.params.each_value.all? do |param|
          key = binding.params[param.name]
          param.component.nil? || key.blank? || version.component?(param.component, key)
        end
      end

      private

      def choose(web)
        return nil if @platform.nil? || web["enabled"] == false

        @platform.web_binding(web["runtime"])
      end
    end
  end
end
