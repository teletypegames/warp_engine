module WarpEngine
  class BuildsService
    def index
      platforms = WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each_with_object({}) do |platform, hash|
        service_class = "WarpEngine::SoftwareUpdater::#{platform.camelize}Service".constantize
        hash[platform] = {
          label: service_class.label,
          kinds: service_class.expected_kinds
        }
      end

      all_kinds = WarpEngine::ReleaseAsset::KINDS

      { platforms: platforms, allKinds: all_kinds }
    end

    def show(name)
      software = WarpEngine::Software.find_by!(name: name)
      service_class = "WarpEngine::SoftwareUpdater::#{software.platform.camelize}Service".constantize
      expected = service_class.expected_kinds

      releases = software.releases.includes(:release_assets).order(updated_at: :desc)

      release_data = releases.each_with_object({}) do |release, hash|
        actual = release.release_assets.map(&:kind)
        hash[release.version] = {
          actual: actual,
          missing: expected - actual
        }
      end

      {
        platform: software.platform,
        expected: expected,
        releases: release_data
      }
    end
  end
end
