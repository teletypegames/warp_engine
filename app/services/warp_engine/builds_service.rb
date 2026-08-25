module WarpEngine
  class BuildsService
    def index
      platforms = WarpEngine::Platform.all.each_with_object({}) do |platform, hash|
        hash[platform.name] = { label: platform.label, kinds: platform.expected_kinds }
      end

      all_kinds = WarpEngine::ReleaseAsset::KINDS

      { platforms: platforms, allKinds: all_kinds }
    end

    def show(name)
      software = WarpEngine::Software.kept.find_by!(name: name)
      expected = WarpEngine::Platform.find!(software.platform).expected_kinds

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
