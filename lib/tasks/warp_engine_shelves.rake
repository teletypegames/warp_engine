namespace :warp_engine do
  namespace :shelves do
    desc "Bring every shelf in line with the catalog (DRY_RUN=1 only prints what would change)"
    task sync: :environment do
      dry_run = ENV["DRY_RUN"] == "1"
      shelves = WarpEngine::Shelves.validate!
      puts "No shelves configured." if shelves.empty?

      shelves.each do |shelf|
        result = WarpEngine::ShelfService.new(shelf).sync!(dry_run: dry_run)
        puts "#{shelf.describe} → #{shelf.directory}#{' (dry run)' if dry_run}"
        puts "  #{result.entries.size} on the shelf"
        result.written.each { |entry| puts "  write   #{entry.file} #{entry.version}" }
        result.removed.each { |file| puts "  remove  #{file}" }
        puts "  index   #{result.index_changed ? 'rewritten' : 'unchanged'}"
        result.skipped.each { |skip| puts "  skipped #{skip}" }
      end
    end

    desc "List what each shelf would hold and what it leaves out (STRICT=1 fails on anything left out)"
    task check: :environment do
      shelves = WarpEngine::Shelves.validate!
      puts "No shelves configured." if shelves.empty?

      skipped_total = 0
      shelves.each do |shelf|
        entries, skipped = WarpEngine::ShelfService.new(shelf).plan
        skipped_total += skipped.size
        puts "#{shelf.describe} → #{shelf.directory}"
        shelf.urls.each { |url| puts "  served  #{url}" }
        entries.each { |entry| puts "  ok      #{entry.file.ljust(shelf.name_length)} #{entry.version}  #{entry.software.name} (#{entry.kind})" }
        skipped.each { |skip| puts "  skipped #{skip}" }
      end

      abort "\nSTRICT: #{skipped_total} software(s) left off a shelf." if ENV["STRICT"] == "1" && skipped_total.positive?
    end
  end
end
