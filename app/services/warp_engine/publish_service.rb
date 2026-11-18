module WarpEngine
  # Publishes a CI upload: hands it to the platform's service, which writes the
  # catalog records, and announces the result.
  class PublishService
    # The ActiveSupport::Notifications event instrumented after every publish,
    # with +platform+, +name+, +version+, +software+, +release+, +source+
    # (WarpEngine::Sync::SOURCES) and +peer+ (the WarpEngine::SyncPeer of a
    # sync, else +nil+) in the payload.
    NOTIFICATION = "warp_engine.publish".freeze

    # A version older than the newest one published would become the latest
    # release and bring back its metadata, so it is refused. Dev versions and
    # versions Gem::Version cannot read are not compared.
    class StaleVersionError < WarpEngine::Error; end

    # Publishes the upload described by +input+ (a WarpEngine::PublishInputDto
    # with +platform+, +name+ and +version+) through WarpEngine::Platform#publish,
    # then instruments NOTIFICATION.
    #
    # [source] where the upload came from: +:ci+ (default) or +:sync+, another
    #          engine (WarpEngine::Sync), whose releases are not pushed on;
    #          stored as the release's +origin+
    # [peer]   the WarpEngine::SyncPeer that pushed it, for +:sync+
    #
    # Returns the WarpEngine::Release. Raises StaleVersionError when the version
    # is older than the newest one published, ArgumentError for an unknown
    # platform, and WarpEngine::Platforms::MissingAssetsError when a required
    # asset was not uploaded.
    def publish(input, source: :ci, peer: nil)
      refuse_stale!(input)
      release = WarpEngine::Platform.find!(input.platform).publish(input.name, input.version)
      release.update!(commit_sha: input.commit) if input.try(:commit).present? && release.respond_to?(:commit_sha)
      if release.respond_to?(:origin) && release.persisted?
        release.update_columns(origin: source.to_s == "sync" ? "sync" : "ci", sync_peer_id: source.to_s == "sync" ? peer&.id : nil)
      end

      ActiveSupport::Notifications.instrument(
        NOTIFICATION,
        platform: input.platform,
        name:     input.name,
        version:  input.version,
        software: release.respond_to?(:software) ? release.software : nil,
        release:  release,
        source:   source.to_sym,
        peer:     peer
      )

      release
    end

    # Returns why publishing +version+ of the software +name+ would be refused
    # as stale (a newer version is published already), or +nil+ when it would
    # not. A <tt>dev-</tt> version is never stale.
    def stale_reason(name, version)
      comparable_version = comparable(version)
      return nil if comparable_version.nil?

      newest = WarpEngine::Software.find_by(name: name)&.releases.to_a.filter_map { |release| comparable(release.version) }.max
      return nil if newest.nil? || comparable_version >= newest

      "#{name} #{version} is older than #{newest}, which is published already"
    end

    private

    def refuse_stale!(input)
      reason = stale_reason(input.name, input.version)
      raise StaleVersionError, reason if reason
    end

    def comparable(version)
      return nil if version.to_s.start_with?("dev-")

      Gem::Version.new(version.to_s.delete_prefix("v"))
    rescue ArgumentError
      nil
    end
  end
end
