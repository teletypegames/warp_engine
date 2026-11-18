namespace :warp_engine do
  namespace :sync do
    find_peer = lambda do |key|
      WarpEngine::SyncPeer.kept.find_by(label: key) || WarpEngine::SyncPeer.kept.find_by(id: key)
    end

    desc "Push releases to a sync peer (by label or id; ALL_PEERS=1 for every outbound one): the newest allowed " \
         "release of every software, ALL=1 every allowed release (a full sync). FILTERED=0 leaves the configured " \
         "filters out; CHANNELS, SOFTWARES (or the second argument), PLATFORMS, CATEGORIES and STATUSES narrow it " \
         "(comma separated); FORCE=1 sends again what the peer has; DRY_RUN=1 only lists"
    task :push, %i[peer software] => :environment do |_task, args|
      peers = ENV["ALL_PEERS"] == "1" ? WarpEngine::SyncPeer.outbound.order(:label).to_a : [ find_peer.call(args[:peer]) ].compact
      abort "No sync peer #{args[:peer].inspect}" if peers.empty?

      criteria = WarpEngine::Sync::Criteria.build(
        mode: ENV["ALL"] == "1" ? "all" : "latest", filtered: ENV["FILTERED"] != "0", channels: ENV["CHANNELS"],
        softwares: args[:software].presence || ENV["SOFTWARES"], platforms: ENV["PLATFORMS"],
        categories: ENV["CATEGORIES"], statuses: ENV["STATUSES"], skip_existing: ENV["FORCE"] != "1"
      )
      puts "#{peers.map(&:label).join(', ')}: #{criteria.summary}"
      service = WarpEngine::SyncService.new
      if ENV["DRY_RUN"] == "1"
        plan = service.plan(criteria)
        plan.releases.each { |release| puts "  would push #{release.software.name} #{release.version}" }
        plan.skipped.each { |line| puts "  skipped #{line}" }
        puts "#{plan.releases.size} release(s) to #{peers.size} peer(s) (dry run)"
      else
        result = service.run(criteria, peers: peers)
        result.skipped.each { |line| puts "  skipped #{line}" }
        puts "#{result.queued} push(es) queued"
      end
    rescue WarpEngine::SyncService::DisabledError, ArgumentError => e
      abort e.message
    end

    desc "Ask a sync peer's transport (by label or id) whether the other side takes us"
    task :check, %i[peer] => :environment do |_task, args|
      peer = find_peer.call(args[:peer])
      abort "No sync peer #{args[:peer].inspect}" if peer.nil?

      result = WarpEngine::SyncService.new.check(peer)
      puts "#{peer.label}: #{result.message}#{" (WarpEngine #{result.version})" if result.version}"
      exit 1 unless result.ok
    end

    desc "Issue a new inbound token for a sync peer (by label or id) into the file FILE (mode 600), never to the screen"
    task :inbound_token, %i[peer] => :environment do |_task, args|
      peer = find_peer.call(args[:peer])
      abort "No sync peer #{args[:peer].inspect}" if peer.nil?
      abort "Set FILE to where the token goes" if ENV["FILE"].blank?

      token = peer.issue_inbound_token!
      File.write(ENV["FILE"], token.plain_token)
      File.chmod(0o600, ENV["FILE"])
      puts "#{peer.label}: inbound token #{token.token_prefix}… written to #{ENV['FILE']}"
    end

    desc "Delete the sync events older than event_retention_days"
    task prune: :environment do
      puts "#{WarpEngine::SyncService.new.prune_events} sync event(s) deleted"
    end
  end
end
