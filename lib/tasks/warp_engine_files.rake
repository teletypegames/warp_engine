namespace :warp_engine do
  namespace :files do
    desc "Move the flat file container (before 3.4) into a <name>/<version>/ folder per release (DRY_RUN=1 only lists)"
    task restructure: :environment do
      dry_run = ENV["DRY_RUN"] == "1"
      result = WarpEngine::ReleaseLayoutService.new.restructure(dry_run: dry_run)
      puts "Entries moved#{' (dry run)' if dry_run}: #{result.count}"
      result.lines.each { |line| puts "  #{line}" }
    end
  end
end
