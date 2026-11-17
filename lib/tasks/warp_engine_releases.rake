namespace :warp_engine do
  namespace :releases do
    desc "Remove the development builds superseded on their branch or not updated for TTL_DAYS days " \
         "(default: the configured dev_release_ttl_days; the kept branches stay; DRY_RUN=1 only lists)"
    task prune_dev: :environment do
      dry = ENV["DRY_RUN"] == "1"
      result = WarpEngine::DevReleaseService.new.prune(ttl_days: (ENV["TTL_DAYS"].presence || WarpEngine.config.dev_release_ttl_days).to_i,
                                                         dry_run: dry)
      puts "Development builds removed#{' (dry run)' if dry}: #{result.count}"
      result.lines.each { |line| puts "  #{line}" }
    end
  end
end
