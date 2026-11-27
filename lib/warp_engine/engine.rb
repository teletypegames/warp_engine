module WarpEngine
  # The Rails engine. It isolates the WarpEngine namespace, appends its
  # migrations to the host's, loads the ActiveAdmin resources of +app/admin+
  # when ActiveAdmin is present together with their stylesheet and script
  # (<tt>warp_engine/admin.css</tt>, <tt>warp_engine/admin.js</tt>; registered on
  # ActiveAdmin 3, linked by the host on ActiveAdmin 4, which has no registry), validates the feeds, directories among them
  # (and the MCP dependency when enabled) after boot, and enqueues a
  # WarpEngine::FeedRefreshJob for the static feeds of a platform on
  # every <tt>warp_engine.publish</tt> notification, and hands the release to
  # WarpEngine::SyncService#dispatch while outbound sync is on (WarpEngine::Sync;
  # a failure there is logged, the publish stands), and every
  # <tt>warp_engine.software_images</tt> notification to
  # WarpEngine::SyncService#dispatch_images, whose settings it checks
  # after boot. It registers the
  # <tt>application/wasm</tt> MIME type the runtimes' files need, unless the
  # host did.
  class Engine < ::Rails::Engine
    isolate_namespace WarpEngine

    initializer "warp_engine.mime_types" do
      Mime::Type.register "application/wasm", :wasm unless Mime::Type.lookup_by_extension(:wasm)
    end

    initializer "warp_engine.ignore_admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(Engine.root.join("app/admin"))
    end

    initializer "warp_engine.portable_migrations" do
      require "warp_engine/portable_migrations"
      ActiveSupport.on_load(:active_record_sqlite3adapter) { WarpEngine::PortableMigrations.install(self) }
      ActiveSupport.on_load(:active_record_postgresqladapter) { WarpEngine::PortableMigrations.install(self) }
    end

    initializer "warp_engine.append_migrations" do |app|
      unless app.root.to_s.start_with?(root.to_s)
        config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
    end

    config.after_initialize do
      WarpEngine::AdminApi::Mcp.ensure_available! if WarpEngine.config.admin_api.mcp?
      WarpEngine::Feeds.validate!
      WarpEngine::Sync.config.validate!.each { |warning| Rails.logger.warn("[WarpEngine] #{warning}") }
      WarpEngine::Forks.config.validate!.each { |warning| Rails.logger.warn("[WarpEngine] #{warning}") }
    end

    initializer "warp_engine.sync" do
      ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
        release = payload[:release]
        if WarpEngine::Sync.outbound? && release.is_a?(WarpEngine::Release)
          WarpEngine::SyncService.new.dispatch(release, source: payload[:source] || :ci)
        end
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Sync] dispatch failed: #{e.class}: #{e.message}")
      end

      ActiveSupport::Notifications.subscribe("warp_engine.software_images") do |*, payload|
        if WarpEngine::Sync.outbound?
          WarpEngine::SyncService.new.dispatch_images(WarpEngine::Software.kept.find_by(id: payload[:software_id]),
                                                      origin: payload[:origin])
        end
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Sync] image dispatch failed: #{e.class}: #{e.message}")
      end

      ActiveSupport::Notifications.subscribe("warp_engine.remove") do |*, payload|
        WarpEngine::SyncService.new.dispatch_removal(payload[:record]) if WarpEngine::Sync.outbound?
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Sync] removal dispatch failed: #{e.class}: #{e.message}")
      end
    end

    initializer "warp_engine.forks" do
      ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
        software = payload[:software]
        WarpEngine::ForkService.new.announce_later(software) if software.is_a?(WarpEngine::Software)
        WarpEngine::SourceVerifyJob.perform_later(software.source.id) if software.is_a?(WarpEngine::Software) && software.source&.public.nil?
      rescue StandardError => e
        Rails.logger.error("[WarpEngine::Forks] after publish: #{e.class}: #{e.message}")
      end
    end

    initializer "warp_engine.feeds" do
      ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
        WarpEngine::FeedRefreshJob.perform_later(payload[:platform]) if WarpEngine::Feeds.any?
        release = payload[:release]
        if release.respond_to?(:dev?) && release.dev? && WarpEngine.scm.configured?
          WarpEngine::PreviewCommentJob.perform_later(release.id)
        end
      end
    end

    initializer "warp_engine.active_admin" do |app|
      if defined?(ActiveAdmin)
        admin_dir = Engine.root.join("app/admin").to_s
        ActiveAdmin.application.load_paths << admin_dir

        app.config.watchable_dirs[admin_dir] = [ :rb ]
        app.config.assets.precompile += %w[warp_engine/admin.css warp_engine/admin.js] if app.config.respond_to?(:assets)
      end
    end

    config.after_initialize do
      if defined?(ActiveAdmin) && ActiveAdmin.application.respond_to?(:register_stylesheet)
        ActiveAdmin.application.register_stylesheet "warp_engine/admin.css"
        ActiveAdmin.application.register_javascript "warp_engine/admin.js"
      end
    end
  end
end
