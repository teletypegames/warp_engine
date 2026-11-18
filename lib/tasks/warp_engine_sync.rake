namespace :warp_engine do
  namespace :sync do
    desc "Push to a sync server (by label or id) the newest allowed release of every software, " \
         "or of SOFTWARE; ALL=1 pushes every allowed release, oldest first"
    task :push, %i[server software] => :environment do |_task, args|
      server = WarpEngine::SyncServer.kept.find_by(label: args[:server]) || WarpEngine::SyncServer.kept.find_by(id: args[:server])
      abort "No sync server #{args[:server].inspect}" if server.nil?

      software = args[:software].presence || ENV["SOFTWARE"].presence
      result = WarpEngine::SyncService.new.backfill(server, software: software, all: ENV["ALL"] == "1")
      puts "#{server.label}: #{result.queued.size} push(es) queued"
      result.skipped.each { |line| puts "  skipped #{line}" }
    rescue WarpEngine::SyncService::DisabledError => e
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
