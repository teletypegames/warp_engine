namespace :warp_engine do
  namespace :outlets do
    desc "List every outlet and what it offers (STRICT=1 fails when an outlet leaves a software out)"
    task check: :environment do
      outlets = WarpEngine::Outlets.validate!
      skipped_total = 0
      outlets.each do |outlet|
        lines = outlet.report
        skipped_total += lines.count { |line| line.start_with?("  skipped") }
        puts outlet.describe
        lines.each { |line| puts line }
      end

      abort "\nSTRICT: #{skipped_total} software(s) left out." if ENV["STRICT"] == "1" && skipped_total.positive?
    end

    desc "Bring every materialized outlet in line with the catalog (DRY_RUN=1 only prints what would change)"
    task sync: :environment do
      dry_run = ENV["DRY_RUN"] == "1"
      outlets = WarpEngine::Outlets.validate!.select { |outlet| outlet.class.materialized? }
      puts "No materialized outlets configured." if outlets.empty?

      outlets.each do |outlet|
        result = outlet.sync!(dry_run: dry_run)
        puts "#{outlet.describe}#{' (dry run)' if dry_run}: #{result.changed? ? 'changed' : 'unchanged'}"
      end
    end
  end
end
