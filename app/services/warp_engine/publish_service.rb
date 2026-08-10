module WarpEngine
  class PublishService
    # Az esemény neve, amit a host lehallgathat. A payload:
    #   platform: String, name: String, version: String,
    #   software: WarpEngine::Software, release: WarpEngine::Release
    NOTIFICATION = "warp_engine.publish".freeze

    def publish(input)
      unless WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.include?(input.platform)
        raise ArgumentError, "Unsupported platform: #{input.platform}"
      end

      release = "WarpEngine::Platforms::#{input.platform.camelize}::Service".constantize
                .new.update(input.name, input.version)

      # A publikálás az egyetlen pont, ahol új build kerül a katalógusba —
      # a host innen tud rá reagálni (értesítés, feed, csatorna-előléptetés)
      # anélkül, hogy modell-callbackre kellene kapaszkodnia.
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
  end
end
