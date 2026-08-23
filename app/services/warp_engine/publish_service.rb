module WarpEngine
  class PublishService

    NOTIFICATION = "warp_engine.publish".freeze

    def publish(input)
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
  end
end
