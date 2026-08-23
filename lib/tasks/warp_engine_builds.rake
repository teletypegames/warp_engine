namespace :warp_engine do
  namespace :builds do
    desc "Checklist of which release assets exist and which the platform expects " \
         "(NAME=slug PLATFORM=godot RELEASES=all ONLY=missing STRICT=1)"
    task check: :environment do
      coverage = WarpEngine::AssetCoverage.new(
        name:     ENV["NAME"],
        platform: ENV["PLATFORM"],
        releases: ENV["RELEASES"] == "all" ? :all : :latest
      )

      checklist = WarpEngine::AssetCoverageChecklist.new(
        coverage, only_missing: ENV["ONLY"] == "missing"
      )
      puts checklist.to_s

      if ENV["STRICT"] == "1" && coverage.totals[:missing].positive?
        abort "\nSTRICT: #{coverage.totals[:missing]} expected assets are missing."
      end
    end
  end
end
