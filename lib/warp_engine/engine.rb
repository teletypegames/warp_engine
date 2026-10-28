module WarpEngine
  # The Rails engine. It isolates the WarpEngine namespace, appends its
  # migrations to the host's, loads the ActiveAdmin resources of +app/admin+
  # when ActiveAdmin is present, validates the shelves (and the MCP dependency
  # when enabled) after boot, and refreshes the shelves of a platform on every
  # <tt>warp_engine.publish</tt> notification.
  class Engine < ::Rails::Engine
    isolate_namespace WarpEngine

    initializer "warp_engine.ignore_admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(Engine.root.join("app/admin"))
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
      WarpEngine::Shelves.validate!
    end

    initializer "warp_engine.shelves" do
      ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
        WarpEngine::Shelves.refresh(platform: payload[:platform])
      end
    end

    initializer "warp_engine.active_admin" do |app|
      if defined?(ActiveAdmin)
        admin_dir = Engine.root.join("app/admin").to_s
        ActiveAdmin.application.load_paths << admin_dir

        app.config.watchable_dirs[admin_dir] = [ :rb ]
      end
    end
  end
end
