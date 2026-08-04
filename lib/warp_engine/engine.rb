module WarpEngine
  class Engine < ::Rails::Engine
    isolate_namespace WarpEngine

    # Az app/admin fájlok ActiveAdmin DSL-t tartalmaznak, nem definiálnak a
    # fájlnévnek megfelelő konstansokat — a Zeitwerk (eager load) nem nyúlhat hozzájuk.
    initializer "warp_engine.ignore_admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(Engine.root.join("app/admin"))
    end

    # Az admin erőforrásokat a HOST ActiveAdmin példánya tölti be; az engine csak
    # regisztrálja a saját app/admin könyvtárát. Auth/téma/route-ok a host dolga.
    initializer "warp_engine.active_admin" do |app|
      if defined?(ActiveAdmin)
        admin_dir = Engine.root.join("app/admin").to_s
        ActiveAdmin.application.load_paths << admin_dir
        # dev módban az engine admin-fájljainak szerkesztése is triggerel reloadot
        app.config.watchable_dirs[admin_dir] = [ :rb ]
      end
    end
  end
end
