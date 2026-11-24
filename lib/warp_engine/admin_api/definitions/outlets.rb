module WarpEngine
  module AdminApi
    module Definitions
      # The +outlets+ resource: the configured outlets (WarpEngine::Outlets) and
      # what each of them offers, the Admin API side of
      # <tt>rake warp_engine:outlets:check</tt>.
      module Outlets
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +outlets+ resource on +api+: the list and the check of one outlet.
        def define(api)
          api.resource(:outlets, label: "Outlets") do |r|
            r.action :get, "/outlets", name: :list, many: true, item: X.outlet,
                     summary: "The configured outlets: the catalog API first, then the host's, in their order" do |ctx|
              ctx.ok(outlets.map { |outlet| outlet_payload(outlet) })
            end

            r.action :get, "/outlets/:key/check", name: :check, item: X.outlet_check,
                     path_params: { key: -> { S.string("The outlet key") } },
                     summary: "What one outlet offers: every title on it and every software it leaves out" do |ctx|
              outlet = outlets.find { |candidate| candidate.key == ctx[:key].to_s }
              raise Error.not_found if outlet.nil?

              ctx.ok(check_payload(outlet))
            end
          end
        end

        # Every configured outlet, checked (WarpEngine::Outlets.validate!). Raises a 409
        # Error with the reason when the configuration is invalid.
        def outlets
          WarpEngine::Outlets.validate!
        rescue WarpEngine::ConfigurationError => e
          raise Error.conflict("The outlet configuration is invalid: #{e.message}")
        end

        # The +Outlet+ answer for +outlet+: its key, type, platforms and description,
        # whether it writes files or answers requests, and the rest of its descriptor.
        def outlet_payload(outlet)
          descriptor = outlet.descriptor.except(:key, :type, :platforms)
          { key: outlet.key, type: outlet.type, platforms: outlet.platforms, description: outlet.describe,
            materialized: outlet.class.materialized?, served: outlet.class.served?,
            details: Statistics.camelize(descriptor.transform_keys(&:to_s)) }
        end

        # The +OutletCheck+ answer for +outlet+: the titles on offer and the skipped
        # softwares with the reason. An outlet without an offer (the catalog API)
        # has both empty and +offer+ false.
        def check_payload(outlet)
          offer = outlet.offer
          items, skips = offer ? offer.plan : [ [], [] ]
          { key: outlet.key, type: outlet.type, offer: !offer.nil?,
            items: items.map do |item|
              { softwareId: item.software.id, name: item.software.name, title: item.software.title,
                version: item.release.version, kind: item.kind }
            end,
            skipped: skips.map { |skip| { softwareId: skip.software.id, name: skip.software.name, reason: skip.reason } } }
        end
      end
    end
  end
end
