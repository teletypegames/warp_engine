module WarpEngine
  class UpdateService
    def update(input)
      unless WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.include?(input.platform)
        raise ArgumentError, "Unsupported platform: #{input.platform}"
      end

      "WarpEngine::SoftwareUpdater::#{input.platform.camelize}Service".constantize.new.update(input.name, input.version)
    end
  end
end
