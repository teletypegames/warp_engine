module WarpEngine
  module AdminApi
    module Definitions
      # The +runtimes+ resource: the installed runtime versions
      # (WarpEngine::RuntimeVersion) and installing a downloaded runtime
      # (WarpEngine::RuntimeInstallService).
      module Runtimes
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +runtimes+ resource on +api+: list, get, and
        # <tt>POST /runtimes/install</tt> (422 for an uploaded runtime, an
        # unknown version or component, or a failed download).
        def define(api)
          api.resource(:runtimes, label: "Runtimes") do |r|
            r.list "/runtimes", summary: "The installed runtime versions", item: X.runtime_version,
                   filters: { name: S.string }, sort: { name: :name, createdAt: :created_at } do |ctx|
              scope = WarpEngine::RuntimeVersion.kept.includes(:runtime_components)
              scope = scope.where(name: ctx[:name]) if ctx[:name].present?
              ctx.list(scope, Admin::RuntimeVersionSerializer)
            end

            r.get "/runtimes/:id", summary: "One installed runtime version", item: X.runtime_version do |ctx|
              ctx.ok(Admin::RuntimeVersionSerializer.render_as_hash(WarpEngine::RuntimeVersion.kept.find(ctx.id)))
            end

            r.action :post, "/runtimes/install", name: :install,
                                                 summary: "Install a downloaded runtime and the components its platforms need",
                                                 item: X.runtime_install, body: X.runtime_install_body do |ctx|
              result = WarpEngine::RuntimeInstallService.new.install(name: ctx[:name].to_s, version: ctx[:version].presence,
                                                                     dry_run: ctx[:dryRun] == true)
              ctx.ok({ name: result.name, version: result.version, fetched: result.fetched, kept: result.kept,
                       components: result.components, dryRun: result.dry_run })
            rescue WarpEngine::RuntimeInstallService::Error, ArgumentError => e
              raise Error.new(422, e.message)
            end
          end
        end
      end
    end
  end
end
