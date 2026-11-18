module WarpEngine
  module AdminApi
    module Definitions
      # The +sync_servers+ and +sync_events+ resources of WarpEngine::Sync: the
      # engines the releases are pushed to, and the log of the pushes. The
      # token of a server is write-only.
      module Sync
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +sync_servers+ and +sync_events+ resources on +api+.
        def define(api)
          sync_servers(api)
          sync_events(api)
        end

        # Declares the +sync_servers+ resource on +api+: list, get, create,
        # update (an empty or missing +secret+ keeps the stored one), delete
        # (soft), <tt>POST /sync_servers/:id/check</tt> (does the other engine
        # accept the token) and <tt>POST /sync_servers/:id/push</tt> (queue the
        # releases it may be missing; 409 while sync is off).
        def sync_servers(api)
          api.resource(:sync_servers, label: "Sync servers") do |r|
            r.list "/sync_servers", summary: "The engines the releases are pushed to", item: X.sync_server,
                   filters: { active: S.boolean }, sort: { label: :label, lastSyncedAt: :last_synced_at } do |ctx|
              scope = WarpEngine::SyncServer.kept
              scope = scope.where(active: ctx[:active]) if ctx.key?(:active)
              ctx.list(scope, Admin::SyncServerSerializer)
            end

            r.get "/sync_servers/:id", summary: "One sync server", item: X.sync_server do |ctx|
              ctx.ok(Admin::SyncServerSerializer.render_as_hash(server(ctx.id)))
            end

            r.create "/sync_servers", summary: "Add a sync server", body: X.sync_server_body,
                     required: %i[label host secret], item: X.sync_server do |ctx|
              record = WarpEngine::SyncServer.new(ctx.attributes)
              ctx.created(Admin::SyncServerSerializer.render_as_hash(ctx.save!(record)))
            end

            r.update "/sync_servers/:id", summary: "Change a sync server", body: X.sync_server_body,
                     item: X.sync_server do |ctx|
              record = server(ctx.id)
              record.assign_attributes(ctx.attributes)
              ctx.ok(Admin::SyncServerSerializer.render_as_hash(ctx.save!(record)))
            end

            r.delete "/sync_servers/:id", summary: "Delete a sync server (soft)" do |ctx|
              server(ctx.id).soft_delete!
              ctx.no_content
            end

            r.action :post, "/sync_servers/:id/check", name: :check, summary: "Ask the server whether it accepts the token",
                     item: X.sync_check do |ctx|
              result = WarpEngine::SyncService.new.check(server(ctx.id))
              ctx.ok({ ok: result.ok, status: result.status, version: result.version, message: result.message })
            end

            r.action :post, "/sync_servers/:id/push", name: :push,
                     summary: "Queue the newest allowed release of every software (or every one with all)",
                     item: X.sync_push,
                     body: S.object({ software: S.string("Only this software, by name"),
                                      all: S.boolean("Every allowed release, oldest first") }) do |ctx|
              result = WarpEngine::SyncService.new.backfill(server(ctx.id), software: ctx[:software].presence,
                                                                            all: ctx[:all] == true)
              ctx.ok({ queued: result.queued.size, skipped: result.skipped })
            rescue WarpEngine::SyncService::DisabledError => e
              raise Error.conflict(e.message)
            end
          end
        end

        # Declares the read-only +sync_events+ resource on +api+: list (newest
        # first) and get.
        def sync_events(api)
          api.resource(:sync_events, label: "Sync events") do |r|
            r.list "/sync_events", summary: "The sync log, newest first", item: X.sync_event,
                   filters: { syncServerId: S.integer, direction: S.enum(WarpEngine::SyncEvent::DIRECTIONS),
                              status: S.enum(WarpEngine::SyncEvent::STATUSES), software: S.string },
                   sort: { createdAt: :created_at }, default_sort: "-createdAt" do |ctx|
              scope = WarpEngine::SyncEvent.all
              scope = scope.where(sync_server_id: ctx[:syncServerId]) if ctx.key?(:syncServerId)
              scope = scope.where(direction: ctx[:direction]) if ctx[:direction].present?
              scope = scope.where(status: ctx[:status]) if ctx[:status].present?
              scope = scope.where(software_name: ctx[:software]) if ctx[:software].present?
              ctx.list(scope, Admin::SyncEventSerializer)
            end

            r.get "/sync_events/:id", summary: "One sync event", item: X.sync_event do |ctx|
              ctx.ok(Admin::SyncEventSerializer.render_as_hash(WarpEngine::SyncEvent.find(ctx.id)))
            end
          end
        end

        # The kept WarpEngine::SyncServer +id+. Raises ActiveRecord::RecordNotFound.
        def server(id) = WarpEngine::SyncServer.kept.find(id)
      end
    end
  end
end
