namespace :warp_engine do
  namespace :sync do
    desc "Push releases to a sync server (by label or id; ALL_SERVERS=1 for every active one): the newest allowed " \
         "release of every software, ALL=1 every allowed release (a full sync). FILTERED=0 leaves the configured " \
         "filters out; CHANNELS, SOFTWARES (or the second argument), PLATFORMS, CATEGORIES and STATUSES narrow it " \
         "(comma separated); FORCE=1 sends again what the server has; DRY_RUN=1 only lists"
    task :push, %i[server software] => :environment do |_task, args|
      servers = if ENV["ALL_SERVERS"] == "1"
        WarpEngine::SyncServer.active.order(:label).to_a
      else
        [ WarpEngine::SyncServer.kept.find_by(label: args[:server]) || WarpEngine::SyncServer.kept.find_by(id: args[:server]) ].compact
      end
      abort "No sync server #{args[:server].inspect}" if servers.empty?

      criteria = WarpEngine::Sync::Criteria.build(
        mode: ENV["ALL"] == "1" ? "all" : "latest", filtered: ENV["FILTERED"] != "0", channels: ENV["CHANNELS"],
        softwares: args[:software].presence || ENV["SOFTWARES"], platforms: ENV["PLATFORMS"],
        categories: ENV["CATEGORIES"], statuses: ENV["STATUSES"], skip_existing: ENV["FORCE"] != "1"
      )
      puts "#{servers.map(&:label).join(', ')}: #{criteria.summary}"
      service = WarpEngine::SyncService.new
      if ENV["DRY_RUN"] == "1"
        plan = service.plan(criteria)
        plan.releases.each { |release| puts "  would push #{release.software.name} #{release.version}" }
        plan.skipped.each { |line| puts "  skipped #{line}" }
        puts "#{plan.releases.size} release(s) to #{servers.size} server(s) (dry run)"
      else
        result = service.run(criteria, servers: servers)
        result.skipped.each { |line| puts "  skipped #{line}" }
        puts "#{result.queued} push(es) queued"
      end
    rescue WarpEngine::SyncService::DisabledError, ArgumentError => e
      abort e.message
    end

    desc "Ask a sync server (by label or id) whether it accepts the stored token"
    task :check, %i[server] => :environment do |_task, args|
      server = WarpEngine::SyncServer.kept.find_by(label: args[:server]) || WarpEngine::SyncServer.kept.find_by(id: args[:server])
      abort "No sync server #{args[:server].inspect}" if server.nil?

      result = WarpEngine::SyncService.new.check(server)
      puts "#{server.label}: #{result.message}#{" (WarpEngine #{result.version})" if result.version}"
      exit 1 unless result.ok
    end

    desc "Delete the sync events older than event_retention_days"
    task prune: :environment do
      puts "#{WarpEngine::SyncService.new.prune_events} sync event(s) deleted"
    end
  end
end
