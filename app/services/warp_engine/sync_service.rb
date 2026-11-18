module WarpEngine
  # Decides which releases go to the sync servers (WarpEngine::SyncServer)
  # and queues their pushes (WarpEngine::SyncPushJob, run by
  # WarpEngine::SyncPushService); also records what other engines push here,
  # checks a server's token and prunes the event log. See WarpEngine::Sync.
  class SyncService
    # Sync is off, so nothing can be queued by hand either.
    class DisabledError < WarpEngine::Error; end

    # The outcome of #check: whether the other engine accepts the token
    # (+ok+), its HTTP +status+, its WarpEngine +version+ (or +nil+) and a
    # +message+ for a person.
    CheckResult = ::Data.define(:ok, :status, :version, :message)

    # What #plan found: the +releases+ to send, in the order they go, and the
    # +skipped+ ones as <tt>"name version: reason"</tt> lines.
    Plan = ::Data.define(:releases, :skipped)

    # The outcome of #run: the +releases+ queued to each of the +servers+, the
    # +skipped+ lines of the Plan, and the WarpEngine::SyncEvent of each push
    # (+nil+ entries while the events are off).
    RunResult = ::Data.define(:releases, :servers, :skipped, :events) do
      # Returns how many pushes were queued.
      def queued = releases.size * servers.size
    end

    # [config] the WarpEngine::Sync::Configuration, by default WarpEngine::Sync.config
    def initialize(config: Sync.config)
      @config = config
      @filter = Sync::Filter.new(config)
    end

    # Queues a push of +release+ to every active sync server, after a publish
    # (the <tt>warp_engine.publish</tt> notification). Does nothing while sync
    # is off, for a release that came by sync (+source+ +:sync+) or when the
    # filters hold it back; the latter is logged as +skipped+ under
    # <tt>events :verbose</tt>.
    #
    # Returns the WarpEngine::SyncEvent of each queued push (+nil+ while the
    # events are off), or an empty Array.
    def dispatch(release, source: :ci)
      return [] unless @config.enabled? && source.to_s != "sync"

      servers = SyncServer.active.to_a
      return [] if servers.empty?

      reason = @filter.reason(release)
      return servers.map { |server| enqueue(release, server) } if reason.nil?

      servers.each { |server| log_skipped(release, server, reason) } if @config.verbose_events?
      []
    end

    # Returns what a run with +criteria+ (WarpEngine::Sync::Criteria) would
    # send, as a Plan: per kept software the narrowings leave in, in name
    # order, the newest release that passes the criteria's filter, or with
    # +all+ every such release, oldest version first so the other side does not refuse
    # the older ones as stale. Does not look at whether sync is enabled.
    def plan(criteria)
      filter = criteria.filter(@config)
      releases = []
      skipped = []
      Software.kept.includes(:releases).order(:name).each do |software|
        next if criteria.reason(software)

        allowed, held = ordered(software.releases.to_a).partition { |release| filter.allowed?(release) }
        skipped.concat(held.map { |release| "#{software.name} #{release.version}: #{filter.reason(release)}" }) if criteria.all?
        picked = criteria.all? ? allowed : allowed.last(1)
        skipped << "#{software.name}: #{held.any? ? filter.reason(held.last) : 'no release published'}" if picked.empty? && !criteria.all?
        releases.concat(picked)
      end
      Plan.new(releases: releases, skipped: skipped)
    end

    # Queues the pushes of #plan for +criteria+ to each of +servers+ (the
    # active ones by default). The pushes keep the criteria, so a push
    # without the configured filters is not held back by them later.
    #
    # Returns a RunResult. Raises DisabledError while sync is off.
    def run(criteria, servers: SyncServer.active.to_a)
      raise DisabledError, "sync is not enabled" unless @config.enabled?

      planned = plan(criteria)
      targets = Array(servers).select { |server| server.active && server.deleted_at.nil? }
      events = targets.flat_map do |server|
        planned.releases.map { |release| enqueue(release, server, criteria: criteria) }
      end
      RunResult.new(releases: planned.releases, servers: targets, skipped: planned.skipped, events: events)
    end

    # Queues pushes to +server+ of what it may be missing: the newest release
    # the filters let go of every kept software (or only of the software named
    # +software+), or with +all+ every such release (#run with default
    # criteria).
    #
    # Returns a RunResult. Raises DisabledError while sync is off and
    # ActiveRecord::RecordNotFound for an unknown +software+.
    def backfill(server, software: nil, all: false)
      Software.kept.find_by!(name: software) if software.present?
      run(Sync::Criteria.build(mode: all ? "all" : "latest", softwares: software, config: @config), servers: [ server ])
    end

    # Records a publish another engine pushed here with its sync token
    # +token+ (an inbound WarpEngine::SyncEvent): +succeeded+ for
    # +http_status+ 200, +skipped+ for 409 (a newer version is here), +failed+
    # otherwise. Returns the event, or +nil+ while the events are off.
    def record_inbound(name:, platform:, version:, http_status:, token:, release: nil, message: nil)
      status = case http_status
      when 200 then "succeeded"
      when 409 then "skipped"
      else "failed"
      end
      SyncEvent.log(direction: "inbound", status: status, software_name: name, platform: platform, version: version,
                    release_id: release&.id, step: "publish", http_status: http_status, message: message,
                    token_prefix: token&.token_prefix)
    end

    # Asks +server+ whether it accepts the stored token, without changing
    # anything there (WarpEngine::Sync::Client#check). Returns a CheckResult.
    def check(server)
      return CheckResult.new(ok: false, status: nil, version: nil, message: "the secret does not decrypt; enter it again") if server.secret.nil?

      response = server.client.check
      case response.status
      when 400 then CheckResult.new(ok: true, status: 400, version: response.version, message: "the token is accepted")
      when 401, 403 then CheckResult.new(ok: false, status: response.status, version: response.version,
                                         message: "the token is refused: it needs the sync scope on #{server.base_url}")
      else CheckResult.new(ok: false, status: response.status, version: response.version, message: response.message)
      end
    rescue Sync::ConnectionError => e
      CheckResult.new(ok: false, status: nil, version: nil, message: e.message)
    end

    # Deletes the events older than +days+ days (by default
    # WarpEngine::Sync::Configuration#event_retention_days). Returns how many.
    def prune_events(days: @config.event_retention_days)
      SyncEvent.where(created_at: ...days.to_i.days.ago).delete_all
    end

    private

    def enqueue(release, server, criteria: nil)
      event = SyncEvent.log(direction: "outbound", status: "queued", sync_server: server, **SyncEvent.release_attributes(release))
      SyncPushJob.perform_later(release.id, server.id, event&.id, criteria&.to_h&.transform_keys(&:to_s))
      event
    end

    def log_skipped(release, server, reason)
      SyncEvent.log(direction: "outbound", status: "skipped", sync_server: server, message: reason,
                    **SyncEvent.release_attributes(release))
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
