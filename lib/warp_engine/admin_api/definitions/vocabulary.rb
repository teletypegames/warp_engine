module WarpEngine
  module AdminApi
    module Definitions
      # The vocabulary resources: software statuses, software categories and platform links.
      module Vocabulary
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +software_statuses+, +software_categories+ and +platform_links+ resources on +api+.
        def define(api)
          crud(api, :software_statuses, label: "Software statuses", model: -> { seeded_statuses },
                    item: X.software_status, body: X.software_status_body, required: %i[key label],
                    serializer: -> { Admin::SoftwareStatusSerializer },
                    filters: { defaultVisible: S.boolean }) do |scope, ctx|
            ctx.key?(:defaultVisible) ? scope.where(default_visible: ctx[:defaultVisible]) : scope
          end

          crud(api, :software_categories, label: "Software categories", model: -> { WarpEngine::SoftwareCategory },
                    item: X.software_category, body: X.software_category_body, required: %i[key label],
                    serializer: -> { Admin::SoftwareCategorySerializer },
                    filters: { needsReview: S.boolean }) do |scope, ctx|
            ctx.key?(:needsReview) ? scope.where(needs_review: ctx[:needsReview]) : scope
          end

          platform_links(api)
        end

        # Declares a resource +name+ with list, get, create, update and delete
        # operations under <tt>/name</tt>.
        #
        # [label]      the resource label
        # [model]      a callable returning the model class
        # [item]       the answer schema
        # [body]       the create and update body schema
        # [required]   the fields required on create
        # [serializer] a callable returning the serializer
        # [filters]    the list filter schemas
        #
        # The block takes the list scope and the Context and returns the filtered scope.
        def crud(api, name, label:, model:, item:, body:, required:, serializer:, filters:, &filter)
          path = "/#{name}"
          api.resource(name, label: label) do |r|
            r.list path, summary: "List the #{label.downcase}", item: item, filters: filters,
                   sort: { position: :position, key: :key } do |ctx|
              ctx.list(filter.call(model.call.all, ctx), serializer.call)
            end

            r.get "#{path}/:id", summary: "One of the #{label.downcase}", item: item do |ctx|
              ctx.ok(serializer.call.render_as_hash(model.call.find(ctx.id)))
            end

            r.create path, summary: "Add to the #{label.downcase}", body: body, required: required, item: item do |ctx|
              ctx.created(serializer.call.render_as_hash(ctx.save!(model.call.new(ctx.attributes))))
            end

            r.update "#{path}/:id", summary: "Change one of the #{label.downcase}", body: body, item: item do |ctx|
              record = model.call.find(ctx.id)
              record.assign_attributes(ctx.attributes)
              ctx.ok(serializer.call.render_as_hash(ctx.save!(record)))
            end

            r.delete "#{path}/:id", summary: "Delete one of the #{label.downcase}" do |ctx|
              model.call.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

        # Declares the +platform_links+ resource on +api+.
        def platform_links(api)
          api.resource(:platform_links, label: "Platform links") do |r|
            r.list "/platform_links", summary: "List the platform links", item: X.platform_link,
                   filters: { platform: S.enum(WarpEngine::Platform.names) },
                   sort: { platform: :platform, position: :position, name: :name } do |ctx|
              scope = WarpEngine::PlatformLink.kept
              scope = scope.where(platform: ctx[:platform]) if ctx[:platform].present?
              ctx.list(scope, Admin::PlatformLinkSerializer)
            end

            r.get "/platform_links/:id", summary: "One platform link", item: X.platform_link do |ctx|
              ctx.ok(Admin::PlatformLinkSerializer.render_as_hash(WarpEngine::PlatformLink.kept.find(ctx.id)))
            end

            r.create "/platform_links", summary: "Add a platform link", body: X.platform_link_body,
                     required: %i[platform name url], item: X.platform_link do |ctx|
              link = ctx.save!(WarpEngine::PlatformLink.new(ctx.attributes))
              ctx.created(Admin::PlatformLinkSerializer.render_as_hash(link))
            end

            r.update "/platform_links/:id", summary: "Change a platform link", body: X.platform_link_body,
                     item: X.platform_link do |ctx|
              link = WarpEngine::PlatformLink.kept.find(ctx.id)
              link.assign_attributes(ctx.attributes)
              ctx.ok(Admin::PlatformLinkSerializer.render_as_hash(ctx.save!(link)))
            end

            r.delete "/platform_links/:id", summary: "Delete a platform link" do |ctx|
              WarpEngine::PlatformLink.kept.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

        # WarpEngine::SoftwareStatus, after seeding its default rows.
        def seeded_statuses
          WarpEngine::SoftwareStatus.seed_defaults!
          WarpEngine::SoftwareStatus
        end
      end
    end
  end
end
