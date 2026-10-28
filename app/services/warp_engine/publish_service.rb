module WarpEngine
  # Publishes a CI upload: hands it to the platform's service, which writes the
  # catalog records, and announces the result.
  class PublishService
    # The ActiveSupport::Notifications event instrumented after every publish,
    # with +platform+, +name+, +version+, +software+ and +release+ in the payload.
    NOTIFICATION = "warp_engine.publish".freeze

    # A version older than the newest one published would become the latest
    # release and bring back its metadata, so it is refused. Dev versions and
    # versions Gem::Version cannot read are not compared.
    class StaleVersionError < StandardError; end

    # Publishes the upload described by +input+ (a WarpEngine::PublishInputDto
    # with +platform+, +name+ and +version+) through the platform service's
    # <tt>update</tt>, then instruments NOTIFICATION.
    #
    # Returns the WarpEngine::Release. Raises StaleVersionError when the version
    # is older than the newest one published, ArgumentError for an unknown
    # platform, and WarpEngine::Platforms::MissingAssetsError when a required
    # asset was not uploaded.
    def publish(input)
      refuse_stale!(input)
      release = WarpEngine::Platform.find!(input.platform).service.update(input.name, input.version)

      ActiveSupport::Notifications.instrument(
        NOTIFICATION,
        platform: input.platform,
        name:     input.name,
        version:  input.version,
        software: release.respond_to?(:software) ? release.software : nil,
        release:  release
      )

      release
    end

    private

    def refuse_stale!(input)
      version = comparable(input.version)
      return if version.nil?

      newest = WarpEngine::Software.find_by(name: input.name)&.releases.to_a.filter_map { |release| comparable(release.version) }.max
      return if newest.nil? || version >= newest

      raise StaleVersionError, "#{input.name} #{input.version} is older than #{newest}, which is published already"
    end

    def comparable(version)
      return nil if version.to_s.start_with?("dev-")

      Gem::Version.new(version.to_s.delete_prefix("v"))
    rescue ArgumentError
      nil
    end
  end
end
