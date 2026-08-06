module WarpEngine
  class PublishService
    def publish(input)
      unless WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.include?(input.platform)
        raise ArgumentError, "Unsupported platform: #{input.platform}"
      end

      "WarpEngine::Platforms::#{input.platform.camelize}::Service".constantize.new.update(input.name, input.version)
    end
  end
end
