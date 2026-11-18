module WarpEngine
  module AdminApi
    module Definitions
      # The +sync_peers+ and +sync_events+ resources of WarpEngine::Sync: the
      # partners this engine syncs with in either direction, and the log. A
      # peer's secret is write-only; its inbound token is shown once, in the
      # answer that issued it.
      module Sync
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +sync_peers+ and +sync_events+ resources on +api+.
        def define(api)
          sync_peers(api)
          sync_events(api)
        end

        # Declares the +sync_peers+ resource on +api+: list, get, create,
        # update (an empty or missing +secret+ keeps the stored one), delete
        # (soft; revokes its inbound token), <tt>POST /sync_peers/:id/check</tt>
        # (does the other side take us), <tt>POST /sync_peers/:id/inbound_token</tt>
        # (issue a new inbound token, shown once), <tt>POST /sync_peers/:id/push</tt>
        # (queue the releases it may be missing) and <tt>POST /sync_peers/run</tt>
        # (the same for several peers); both pushes take WarpEngine::Sync::Criteria
        # and +dryRun+, and answer 409 while outbound sync is off.
        def sync_peers(api)
          api.resource(:sync_peers, label: "Sync peers") do |r|
            r.list "/sync_peers", summary: "The engines this one syncs with", item: X.sync_peer,
                   filters: { outboundEnabled: S.boolean, inboundEnabled: S.boolean, transport: S.string },
                   sort: { label: :label, lastSyncedAt: :last_synced_at } do |ctx|
              scope = WarpEngine::SyncPeer.kept
              scope = scope.where(outbound_enabled: ctx[:outboundEnabled]) if ctx.key?(:outboundEnabled)
              scope = scope.where(inbound_enabled: ctx[:inboundEnabled]) if ctx.key?(:inboundEnabled)
              scope = scope.where(transport: ctx[:transport]) if ctx[:transport].present?
              ctx.list(scope, Admin::SyncPeerSerializer)
            end

            r.get "/sync_peers/:id", summary: "One sync peer", item: X.sync_peer do |ctx|
              ctx.ok(Admin::SyncPeerSerializer.render_as_hash(peer(ctx.id)))
            end

            r.create "/sync_peers", summary: "Add a sync peer", body: X.sync_peer_body, required: %i[label],
                                    item: X.sync_peer do |ctx|
              record = WarpEngine::SyncPeer.new(ctx.attributes)
              ctx.created(Admin::SyncPeerSerializer.render_as_hash(ctx.save!(record)))
            end

            r.update "/sync_peers/:id", summary: "Change a sync peer", body: X.sync_peer_body, item: X.sync_peer do |ctx|
              record = peer(ctx.id)
              record.assign_attributes(ctx.attributes)
              ctx.ok(Admin::SyncPeerSerializer.render_as_hash(ctx.save!(record)))
            end

            r.delete "/sync_peers/:id", summary: "Delete a sync peer (soft) and revoke its inbound token" do |ctx|
              record = peer(ctx.id)
              record.inbound_token&.revoke!
              record.soft_delete!
              ctx.no_content
            end

            r.action :post, "/sync_peers/:id/check", name: :check, summary: "Ask the peer's transport whether the other side takes us",
                                                     item: X.sync_check do |ctx|
              result = WarpEngine::SyncService.new.check(peer(ctx.id))
              ctx.ok({ ok: result.ok, status: result.status, version: result.version, message: result.message })
            end

            r.action :post, "/sync_peers/:id/inbound_token", name: :inbound_token, status: 201,
                     summary: "Issue a new inbound token for the peer (the old one stops working); shown in this answer only",
                     item: X.sync_inbound_token do |ctx|
              record = peer(ctx.id)
              raise Error.conflict("#{record.label} does not push here (inboundEnabled is false)") unless record.inbound_enabled

              token = record.issue_inbound_token!
              ctx.created({ tokenPrefix: token.token_prefix, plainToken: token.plain_token })
            end

            r.action :post, "/sync_peers/:id/push", name: :push,
                     summary: "Queue releases for the peer: the newest allowed of every software, or every one with all",
                     item: X.sync_push, body: X.sync_run_body do |ctx|
              ctx.ok(run(ctx, [ peer(ctx.id) ]))
            end

            r.action :post, "/sync_peers/run", name: :run,
                     summary: "Queue releases for every outbound peer, or the ones in peerIds",
                     item: X.sync_push,
                     body: S.object(X.sync_run_body[:properties].merge(peerIds: S.array(S.integer, "Default: every outbound peer"))) do |ctx|
              ids = Array(ctx[:peerIds]).map(&:to_i)
              peers = ids.any? ? WarpEngine::SyncPeer.outbound.where(id: ids).to_a : WarpEngine::SyncPeer.outbound.to_a
              ctx.ok(run(ctx, peers))
            end
          end
        end

        # Declares the read-only +sync_events+ resource on +api+: list (newest
        # first), get, a software's events and its sync state per peer.
        def sync_events(api)
          api.resource(:sync_events, label: "Sync events") do |r|
            r.list "/sync_events", summary: "The sync log, newest first", item: X.sync_event,
                   filters: { syncPeerId: S.integer, softwareId: S.integer, direction: S.enum(WarpEngine::SyncEvent::DIRECTIONS),
                              status: S.enum(WarpEngine::SyncEvent::STATUSES), software: S.string("Software name") },
                   sort: { createdAt: :created_at }, default_sort: "-createdAt" do |ctx|
              ctx.list(events(ctx, WarpEngine::SyncEvent.all), Admin::SyncEventSerializer)
            end

            r.get "/sync_events/:id", summary: "One sync event", item: X.sync_event do |ctx|
              ctx.ok(Admin::SyncEventSerializer.render_as_hash(WarpEngine::SyncEvent.find(ctx.id)))
            end

            r.action :get, "/softwares/:softwareId/sync_events", name: :for_software, many: true,
                     summary: "The newest 100 sync events of one software", item: X.sync_event,
                     query: { direction: S.enum(WarpEngine::SyncEvent::DIRECTIONS) } do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              scope = software.sync_events.limit(100)
              scope = scope.where(direction: ctx[:direction]) if ctx[:direction].present?
              ctx.ok(Admin::SyncEventSerializer.render_as_hash(scope.to_a))
            end

            r.action :get, "/softwares/:softwareId/sync_status", name: :status, many: true,
                     summary: "The sync state of one software: per peer and direction, the newest event and why it would not go",
                     item: X.sync_status do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              lines = WarpEngine::SyncService.new.status(software)
              ctx.ok(lines.map do |line|
                { peerId: line.peer.id, peer: line.peer.label, direction: line.direction, reason: line.reason,
                  event: line.event && Admin::SyncEventSerializer.render_as_hash(line.event) }
              end)
            end
          end
        end

        # Narrows the events +scope+ by the filters of +ctx+.
        def events(ctx, scope)
          scope = scope.where(sync_peer_id: ctx[:syncPeerId]) if ctx.key?(:syncPeerId)
          scope = scope.where(software_id: ctx[:softwareId]) if ctx.key?(:softwareId)
          scope = scope.where(direction: ctx[:direction]) if ctx[:direction].present?
          scope = scope.where(status: ctx[:status]) if ctx[:status].present?
          scope = scope.where(software_name: ctx[:software]) if ctx[:software].present?
          scope
        end

        # Plans (with +dryRun+) or queues a run to +peers+ from the body of
        # +ctx+ and returns the SyncPush answer. Raises a 400 Error for an
        # unknown channel and a 409 Error while outbound sync is off.
        def run(ctx, peers)
          criteria = WarpEngine::Sync::Criteria.build(
            mode: ctx[:all] == true ? "all" : "latest", filtered: ctx.key?(:filtered) ? ctx[:filtered] : true,
            channels: ctx[:channels], softwares: ctx[:softwares].presence || ctx[:software], platforms: ctx[:platforms],
            categories: ctx[:categories], statuses: ctx[:statuses],
            skip_existing: ctx.key?(:skipExisting) ? ctx[:skipExisting] : true
          )
          service = WarpEngine::SyncService.new
          if ctx[:dryRun] == true
            plan = service.plan(criteria)
            return push_answer(plan.releases, peers, plan.skipped, dry_run: true)
          end

          result = service.run(criteria, peers: peers)
          push_answer(result.releases, result.peers, result.skipped, dry_run: false)
        rescue ArgumentError => e
          raise Error.bad_request(e.message)
        rescue WarpEngine::SyncService::DisabledError => e
          raise Error.conflict(e.message)
        end

        # The SyncPush answer: the +releases+ (software and version), the
        # +peers+ (ids), the pushes queued (none on a dry run) and the
        # +skipped+ lines.
        def push_answer(releases, peers, skipped, dry_run:)
          { dryRun: dry_run, queued: dry_run ? 0 : releases.size * peers.size, peers: peers.map(&:id),
            releases: releases.map { |release| { software: release.software.name, version: release.version } },
            skipped: skipped }
        end

        # The kept WarpEngine::SyncPeer +id+. Raises ActiveRecord::RecordNotFound.
        def peer(id) = WarpEngine::SyncPeer.kept.find(id)
      end
    end
  end
end
