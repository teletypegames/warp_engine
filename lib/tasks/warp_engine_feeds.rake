namespace :warp_engine do
  namespace :feeds do
    desc "List every feed and what it offers (STRICT=1 fails when a feed leaves a software out)"
    task check: :environment do
      feeds = WarpEngine::Feeds.validate!
      skipped_total = 0
      feeds.each do |feed|
        lines = feed.report
        skipped_total += lines.count { |line| line.start_with?("  skipped") }
        puts feed.describe
        lines.each { |line| puts line }
      end

      abort "\nSTRICT: #{skipped_total} software(s) left out." if ENV["STRICT"] == "1" && skipped_total.positive?
    end

    desc "Bring every static feed in line with the catalog (DRY_RUN=1 only prints what would change)"
    task sync: :environment do
      dry_run = ENV["DRY_RUN"] == "1"
      feeds = WarpEngine::Feeds.validate!.select { |feed| feed.class.static? }
      puts "No static feeds configured." if feeds.empty?

      feeds.each do |feed|
        result = feed.sync!(dry_run: dry_run)
        puts "#{feed.describe}#{' (dry run)' if dry_run}: #{result.changed? ? 'changed' : 'unchanged'}"
        result.lines.each { |line| puts line } if result.respond_to?(:lines)
      end
    end
  end
end
