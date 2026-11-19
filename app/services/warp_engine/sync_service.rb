module WarpEngine
  # Decides which releases go to the sync peers (WarpEngine::SyncPeer) and
  # queues their pushes (WarpEngine::SyncPushJob, run by
  # WarpEngine::SyncPushService); also records what peers push here, checks
  # a peer's transport, tells a software's sync state and prunes the event
  # log. See WarpEngine::Sync.
  class SyncService
    # Outbound sync is off, so nothing can be queued by hand either.
    class DisabledError < WarpEngine::Error; end

    # What #plan found: the +releases+ to send, in the order they go, and the
    # +skipped+ ones as <tt>"name version: reason"</tt> lines.
    Plan = ::Data.define(:releases, :skipped)

    # The outcome of #run: the +releases+ queued to each of the +peers+, the
    # +skipped+ lines of the Plan, and the WarpEngine::SyncEvent of each push
    # (+nil+ entries while the events are off).
    RunResult = ::Data.define(:releases, :peers, :skipped, :events) do
      # Returns how many pushes were queued.
      def queued = releases.size * peers.size
    end

    # One line of #status: the +peer+, the +direction+, its newest
    # WarpEngine::SyncEvent (or +nil+) and, outbound, why the newest release
    # would not go (+reason+, or +nil+).
    StatusLine = ::Data.define(:peer, :direction, :event, :reason)

    # [config] the WarpEngine::Sync::Configuration, by default WarpEngine::Sync.config
    def initialize(config: Sync.config)
      @config = config
      @filter = Sync::Filter.new(config.outbound)
    end

    # Queues a push of +release+ to every peer that takes outbound pushes,
    # after a publish (the <tt>warp_engine.publish</tt> notification). Does
    # nothing while outbound sync is off, for a release that came by sync
    # (+source+ +:sync+ or its +origin+) or when the filters hold it back; the
    # latter is logged as +skipped+ under <tt>events :verbose</tt>.
    #
    # Returns the WarpEngine::SyncEvent of each queued push (+nil+ while the
    # events are off), or an empty Array.
    def dispatch(release, source: :ci)
      return [] unless @config.outbound.enabled? && source.to_s != "sync" && !release.try(:synced?)

      SyncPeer.outbound.to_a.filter_map do |peer|
        reason = @filter.for(peer).reason(release)
        next enqueue(release, peer) if reason.nil?

        log_skipped(release, peer, reason) if @config.verbose_events?
        nil
      end
    end

    # Queues a push of the gallery of +software+ (WarpEngine::SyncImagesJob)
    # to every peer that takes outbound pushes over a transport that carries
    # images, after a change of its images (the
    # <tt>warp_engine.software_images</tt> notification). Does nothing while
    # outbound sync is off, for images that came by sync (+origin+
    # <tt>"sync"</tt>), for a peer the newest release published here would
    # not go to, and for a peer with a gallery push still queued.
    #
    # Returns the WarpEngine::SyncEvent of each queued push (+nil+ entries
    # while the events are off), or an empty Array.
    def dispatch_images(software, origin: "local")
      return [] unless @config.outbound.enabled? && origin.to_s != "sync" && software

      newest = Release.latest(software.releases.kept.to_a.reject { |release| release.try(:synced?) })
      return [] if newest.nil?

      SyncPeer.outbound.to_a.select { |peer| images_go?(software, peer, newest) }.map { |peer| enqueue_images(software, peer) }
    end

    # Returns what a run with +criteria+ (WarpEngine::Sync::Criteria) would
    # send to +peer+ (a WarpEngine::SyncPeer whose channels narrow it, or
    # +nil+ for none), as a Plan: per kept software the narrowings leave in, in name
    # order, the newest release that passes the criteria's filter, or with
    # +all+ every such release, oldest version first so the other side does
    # not refuse the older ones as stale. Releases that came by sync are left
    # out. Does not look at whether outbound sync is enabled.
    def plan(criteria, peer: nil)
      filter = criteria.filter(@config.outbound).for(peer)
      releases = []
      skipped = []
      Software.kept.includes(:releases).order(:name).each do |software|
        next if criteria.reason(software)

        candidates = ordered(software.releases.to_a.reject { |release| release.try(:synced?) })
        allowed, held = candidates.partition { |release| filter.allowed?(release) }
        skipped.concat(held.map { |release| "#{software.name} #{release.version}: #{filter.reason(release)}" }) if criteria.all?
        picked = criteria.all? ? allowed : allowed.last(1)
        skipped << "#{software.name}: #{held.any? ? filter.reason(held.last) : 'no release published here'}" if picked.empty? && !criteria.all?
        releases.concat(picked)
      end
      Plan.new(releases: releases, skipped: skipped)
    end

    # Queues the pushes of #plan for +criteria+ to each of +peers+ (every
    # peer that takes outbound pushes by default), each peer's plan narrowed
    # to its channels; the RunResult's +releases+ and +skipped+ are those of
    # the single peer, or of the plan without a peer for several. The pushes keep the
    # criteria, so a push without the configured filters is not held back by
    # them later.
    #
    # Returns a RunResult. Raises DisabledError while outbound sync is off.
    def run(criteria, peers: SyncPeer.outbound.to_a)
      raise DisabledError, "outbound sync is not enabled" unless @config.outbound.enabled?

      targets = Array(peers).select { |peer| peer.outbound_enabled && peer.deleted_at.nil? }
      planned = plan(criteria, peer: targets.one? ? targets.first : nil)
      events = targets.flat_map do |peer|
        plan(criteria, peer: peer).releases.map { |release| enqueue(release, peer, criteria: criteria) }
      end
      RunResult.new(releases: planned.releases, peers: targets, skipped: planned.skipped, events: events)
    end

    # Queues pushes to +peer+ of what it may be missing: the newest release
    # the filters let go of every kept software (or only of the software named
    # +software+), or with +all+ every such release (#run with default criteria).
    #
    # Returns a RunResult. Raises DisabledError while outbound sync is off and
    # ActiveRecord::RecordNotFound for an unknown +software+.
    def backfill(peer, software: nil, all: false)
      Software.kept.find_by!(name: software) if software.present?
      run(Sync::Criteria.build(mode: all ? "all" : "latest", softwares: software, config: @config.outbound), peers: [ peer ])
    end

    # Records a publish +peer+ pushed here with +token+ (an inbound
    # WarpEngine::SyncEvent): +succeeded+ for +http_status+ 200, +skipped+ for
    # 403 and 409 (refused by the inbound settings, or a newer or own version
    # is here), +failed+ otherwise. Returns the event, or +nil+ while the
    # events are off.
    def record_inbound(name:, platform:, version:, http_status:, token:, peer: nil, release: nil, message: nil)
      status = case http_status
      when 200 then "succeeded"
      when 403, 409 then "skipped"
      else "failed"
      end
      software_id = release&.software_id || Software.kept.where(name: name).pick(:id)
      SyncEvent.log(direction: "inbound", status: status, sync_peer: peer, software_id: software_id, software_name: name,
                    platform: platform, version: version, release_id: release&.id, step: "publish",
                    http_status: http_status, message: message, token_prefix: token&.token_prefix)
    end

    # Asks +peer+'s transport whether the other side answers and takes our
    # credentials (WarpEngine::Sync::Transport#check). Returns a
    # WarpEngine::Sync::Transport::CheckResult.
    def check(peer)
      peer.transport_instance.check
    rescue WarpEngine::Error => e
      Sync::Transport::CheckResult.new(ok: false, status: nil, version: nil, message: e.message)
    end

    # Returns the sync state of +software+, a StatusLine per kept peer and
    # direction the peer takes part in: outbound for a peer that takes
    # outbound pushes (with why the newest release would not go), inbound
    # for one that may push here.
    def status(software)
      newest = Release.latest(software.releases.to_a.reject { |release| release.try(:synced?) })
      SyncPeer.kept.order(:label).flat_map do |peer|
        reason = newest ? @filter.for(peer).reason(newest) : "no release published here"
        reason ||= "outbound sync is off" unless @config.outbound.enabled?
        lines = []
        lines << StatusLine.new(peer: peer, direction: "outbound", event: newest_event(software, peer, "outbound"), reason: reason) if peer.outbound_enabled
        lines << StatusLine.new(peer: peer, direction: "inbound", event: newest_event(software, peer, "inbound"), reason: nil) if peer.inbound_enabled
        lines
      end
    end

    # Deletes the events older than +days+ days (by default
    # WarpEngine::Sync::Configuration#event_retention_days). Returns how many.
    def prune_events(days: @config.event_retention_days)
      SyncEvent.where(created_at: ...days.to_i.days.ago).delete_all
    end

    private

    def enqueue(release, peer, criteria: nil)
      event = SyncEvent.log(direction: "outbound", status: "queued", sync_peer: peer, **SyncEvent.release_attributes(release))
      SyncPushJob.perform_later(release.id, peer.id, event&.id, criteria&.to_h&.transform_keys(&:to_s))
      event
    end

    def images_go?(software, peer, newest)
      return false unless peer.transport_class&.images? && @filter.for(peer).reason(newest).nil?

      !SyncEvent.where(sync_peer_id: peer.id, software_id: software.id, step: "images", status: "queued").exists?
    end

    def enqueue_images(software, peer)
      event = SyncEvent.log(direction: "outbound", status: "queued", sync_peer: peer, step: "images",
                            software_id: software.id, software_name: software.name, platform: software.platform)
      SyncImagesJob.set(wait: 10.seconds).perform_later(software.id, peer.id, event&.id)
      event
    end

    def log_skipped(release, peer, reason)
      SyncEvent.log(direction: "outbound", status: "skipped", sync_peer: peer, message: reason,
                    **SyncEvent.release_attributes(release))
    end

    def newest_event(software, peer, direction)
      SyncEvent.where(software_id: software.id, sync_peer_id: peer.id, direction: direction).recent.first
    end

    def ordered(releases)
      releases.sort_by { |release| [ comparable(release.version), release.created_at || Time.at(0), release.id ] }
    end

    def comparable(version)
      Gem::Version.new(version.to_s.delete_prefix("v"))
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
