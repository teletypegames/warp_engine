module WarpEngine
  module AdminApi
    module Definitions
      # The +feeds+ resource: the configured feeds (WarpEngine::Feeds) and
      # what each of them offers, the Admin API side of
      # <tt>rake warp_engine:feeds:check</tt>.
      module Feeds
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +feeds+ resource on +api+: the list and the check of one feed.
        def define(api)
          api.resource(:feeds, label: "Feeds") do |r|
            r.action :get, "/feeds", name: :list, many: true, item: X.feed,
                     summary: "The configured feeds: the catalog API first, then the host's, in their order" do |ctx|
              ctx.ok(feeds.map { |feed| feed_payload(feed) })
            end

            r.action :get, "/feeds/:key/check", name: :check, item: X.feed_check,
                     path_params: { key: -> { S.string("The feed key") } },
                     summary: "What one feed offers: every title on it and every software it leaves out" do |ctx|
              feed = feeds.find { |candidate| candidate.key == ctx[:key].to_s }
              raise Error.not_found if feed.nil?

              ctx.ok(check_payload(feed))
            end
          end
        end

        # Every configured feed, checked (WarpEngine::Feeds.validate!). Raises a 409
        # Error with the reason when the configuration is invalid.
        def feeds
          WarpEngine::Feeds.validate!
        rescue WarpEngine::ConfigurationError => e
          raise Error.conflict("The feed configuration is invalid: #{e.message}")
        end

        # The +Feed+ answer for +feed+: its key, type, platforms and description,
        # whether it writes files or answers requests, and the rest of its descriptor.
        def feed_payload(feed)
          descriptor = feed.descriptor.except(:key, :type, :platforms)
          { key: feed.key, type: feed.type, platforms: feed.platforms, description: feed.describe,
            static: feed.class.static?, dynamic: feed.class.dynamic?,
            details: Statistics.camelize(descriptor.transform_keys(&:to_s)) }
        end

        # The +FeedCheck+ answer for +feed+: the titles in its selection and the skipped
        # softwares with the reason. A feed without a selection (the catalog API)
        # has both empty and +selection+ false.
        def check_payload(feed)
          selection = feed.selection
          items, skips = selection ? selection.plan : [ [], [] ]
          { key: feed.key, type: feed.type, selection: !selection.nil?,
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
