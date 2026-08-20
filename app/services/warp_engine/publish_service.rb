module WarpEngine
  class PublishService

    NOTIFICATION = "warp_engine.publish".freeze

    def publish(input)
      unless WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.include?(input.platform)
        raise ArgumentError, "Unsupported platform: #{input.platform}"
      end

      release = "WarpEngine::Platforms::#{input.platform.camelize}::Service".constantize
                .new.update(input.name, input.version)

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
