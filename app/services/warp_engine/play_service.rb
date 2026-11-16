module WarpEngine
  # Resolves what the web player page of a release needs: the platform
  # binding, the installed runtime version, the payload asset and the
  # parameters. Without a binding key it is the one the release was
  # published with (+web_binding+, +runtime_version+); with a key it is that
  # enabled binding of the platform, in the release's runtime version when it
  # is the release's own binding, else in the runtime's current version.
  # Applies the access policy to the payload.
  class PlayService
    include AccessPolicyGuard

    # Raised when there is nothing to play: no such software, release or
    # binding, the runtime or a component is not installed, or the release
    # has no payload asset.
    class NotFound < WarpEngine::Error; end

    # What the page is built from.
    #
    # [software]        the WarpEngine::Software
    # [release]         the WarpEngine::Release
    # [binding]         the WarpEngine::Platform::WebBinding
    # [runtime_version] the WarpEngine::RuntimeVersion it plays in
    # [payload]         the payload WarpEngine::ReleaseAsset
    # [params]          the runtime parameters, a Hash with String keys
    # [template]        the runtime's page template, a String
    Page = ::Data.define(:software, :release, :binding, :runtime_version, :payload, :params, :template) do
      # Returns the payload's path relative to the file container.
      def payload_path = payload.path.to_s.delete_prefix("#{WarpEngine.config.file_container_path.to_s.chomp('/')}/")

      # Returns +true+ when the page must be served cross-origin isolated.
      def isolated? = binding.isolated
    end

    # Returns the Page of the release +version+ of the software +name+, in
    # the binding +binding+ (a key; blank for the release's own). +subject+
    # is the caller for the access policy (+nil+ when anonymous); +authorize+
    # +false+ skips the policy (the maintenance checks). Raises NotFound, or
    # WarpEngine::AccessDenied when the policy refuses the payload.
    def page(name:, version:, binding: nil, subject: nil, authorize: true)
      software = WarpEngine::Software.kept.find_by(name: name.to_s) || raise(NotFound, "no software #{name}")
      release = software.releases.find_by(version: version.to_s) || raise(NotFound, "no release #{version}")
      platform = WarpEngine::Platform.find(software.platform) || raise(NotFound, "unknown platform")
      chosen, runtime_version = resolve(platform, release, binding)
      raise NotFound, "the release does not play on the web" if chosen.nil? || runtime_version.nil? || runtime_version.deleted_at
      raise NotFound, "#{runtime_version.label} lacks a component" unless Publish::WebBinder.components_installed?(runtime_version, chosen)

      payload = release.release_assets.find { |asset| asset.kind == chosen.payload } || raise(NotFound, "no #{chosen.payload} asset")
      authorize_download!(asset: payload, subject: subject) if authorize

      definition = chosen.runtime_object.definition
      params = definition.resolve_params(chosen.params, release.web_options.to_h["params"])
      Page.new(software, release, chosen, runtime_version, payload, params, definition.template_source)
    end

    private

    def resolve(platform, release, key)
      if key.blank?
        return [ nil, nil ] if release.web_binding.blank?

        return [ platform.web_binding(release.web_binding), release.runtime_version ]
      end

      chosen = platform.web_binding(key)
      return [ nil, nil ] if chosen.nil? || release.web_options.to_h["enabled"] == false
      return [ chosen, release.runtime_version ] if chosen.key == release.web_binding && release.runtime_version

      [ chosen, chosen.runtime_object&.current_version ]
    end
  end
end
