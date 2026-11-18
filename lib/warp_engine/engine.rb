module WarpEngine
  # The Rails engine. It isolates the WarpEngine namespace, appends its
  # migrations to the host's, loads the ActiveAdmin resources of +app/admin+
  # when ActiveAdmin is present together with their stylesheet and script
  # (<tt>warp_engine/admin.css</tt>, <tt>warp_engine/admin.js</tt>; registered on
  # ActiveAdmin 3, linked by the host on ActiveAdmin 4, which has no registry), validates the outlets, shelves among them
  # (and the MCP dependency when enabled) after boot, and enqueues a
  # WarpEngine::OutletRefreshJob for the materialized outlets of a platform on
  # every <tt>warp_engine.publish</tt> notification, and hands the release to
  # WarpEngine::SyncService#dispatch while outbound sync is on (WarpEngine::Sync;
  # a failure there is logged, the publish stands), whose settings it checks
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
      WarpEngine::Outlets.validate!
      WarpEngine::Sync.config.validate!.each { |warning| Rails.logger.warn("[WarpEngine] #{warning}") }
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
    end

    initializer "warp_engine.outlets" do
      ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
        WarpEngine::OutletRefreshJob.perform_later(payload[:platform]) if WarpEngine::Outlets.any?
        release = payload[:release]
        if release.respond_to?(:dev?) && release.dev? && WarpEngine.forge.configured?
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
