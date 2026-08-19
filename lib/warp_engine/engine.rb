module WarpEngine
  class Engine < ::Rails::Engine
    isolate_namespace WarpEngine

    # Az app/admin fájlok ActiveAdmin DSL-t tartalmaznak, nem definiálnak a
    # fájlnévnek megfelelő konstansokat — a Zeitwerk (eager load) nem nyúlhat hozzájuk.
    initializer "warp_engine.ignore_admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(Engine.root.join("app/admin"))
    end

    # A jövőbeli katalógus-migrációk az engine db/migrate-jéből futnak a host
    # rails db:migrate-jével, másolás nélkül.
    #
    # FONTOS: emiatt az engine és a host migrációi EGY névtérben vannak, és két
    # azonos verziószám a host `db:migrate`-jét indulás előtt megállítja
    # (DuplicateMigrationVersionError) — nem a miénket, hanem az övét, az egész
    # alkalmazásban. Az engine migrációi ezért **valódi, másodperc-pontosságú
    # időbélyeget** kapnak (20260819093412), soha nem kerek kézzel írt számot
    # (20260819000001): pont az utóbbiakra ír rá egy host, ami ugyanaznap ugyanezzel
    # a szokással ír migrációt. Így ütközött a device_grants a katalógus-API
    # `carry_the_store_config_in_the_registry`-jével.
    initializer "warp_engine.append_migrations" do |app|
      unless app.root.to_s.start_with?(root.to_s)
        config.paths["db/migrate"].expanded.each do |path|
          app.config.paths["db/migrate"] << path
        end
      end
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
