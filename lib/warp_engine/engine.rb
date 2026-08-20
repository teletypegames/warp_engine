module WarpEngine
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

    initializer "warp_engine.active_admin" do |app|
      if defined?(ActiveAdmin)
        admin_dir = Engine.root.join("app/admin").to_s
        ActiveAdmin.application.load_paths << admin_dir

        app.config.watchable_dirs[admin_dir] = [ :rb ]
      end
    end
  end
end
