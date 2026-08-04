# WarpEngine

Mountable Rails engine: retro szoftverkatalógus CI-pipeline-ból hívható release-updaterrel,
publikus read-only JSON API-val és a host adminjába betöltődő ActiveAdmin erőforrásokkal.

## Mit ad

- **Modellek**: `Software`, `Release`, `ReleaseAsset`, `ExternalLink`, `PlatformLink`,
  `Image`, `SoftwareImage`, `Download` (mind `WarpEngine::` alatt, prefix nélküli táblákkal)
- **Updater**: `GET /update?platform=&name=&version=` (`X-Update-Secret` fejléc vagy
  `?secret=`) — a CI a build-artifactokat a `file_container_path` alá másolja
  (`<name>-<version>*` konvencióval), majd meghívja az endpointot; az updater kicsomagol,
  metadatát parse-ol, és upserteli a Software/Release/ReleaseAsset/ExternalLink rekordokat.
  Támogatott platformok: tic80, ebitengine, love, c64, godot, bevy, phaser.
- **Publikus API**: `/api/software`, `/api/software/highlighted`, `/api/builds`,
  `/api/softwares/:name/builds`, `/api/image/:id`, `/api/download?path=`, `/file/*path`
- **Admin**: ActiveAdmin resource-fájlok (softwares a 3 szintű beágyazott formmal,
  releases, external links, platform links, images orphan-kezeléssel, Files fájlkezelő
  picker móddal, download stats) — a host ActiveAdmin példányába töltődnek be.

## Telepítés

```ruby
# Gemfile
gem "warp_engine", path: "../../libs/ruby/warp_engine"
```

```sh
rails g warp_engine:install   # initializer + create_warp_engine_tables migráció
rails db:migrate
```

```ruby
# config/routes.rb — utolsó sorként, hogy a host route-jai nyerjenek
mount WarpEngine::Engine => "/"
```

## Konfiguráció

```ruby
Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    c.file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
    c.image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
    c.update_secret        = ENV["UPDATE_SECRET"] # nil => /update mindig elutasít
    # Ha a host modelljei is használnak katalógus-képeket:
    c.image_owners = [
      {
        label: "member",
        image_ids: -> { Member.where.not(image_id: nil).distinct.pluck(:image_id) },
        usage_label: ->(image) { "member" if Member.where(image_id: image.id).exists? }
      }
    ]
  end
end
```

## Host-elvárások

- **ActiveAdmin + Devise a hostban él**: auth, téma, assetek és a `/admin` route-ok a
  host dolga; az engine csak resource-fájlokat ad a `ActiveAdmin.application.load_paths`-hoz.
- **Files picker JS**: a release-asset path-mezők melletti fájlkiválasztó a host
  `active_admin.js`-ében élő pár soros JS-re támaszkodik (iframe a
  `/admin/files?picker=1&field=<dom_id>` címre) — új hostba ezt is át kell venni.
- **apipie**: ha a host apipie-dokut generál, vegye fel a matcherbe:
  `"#{WarpEngine::Engine.root}/app/controllers/**/*.rb"`.

## Viselkedési megjegyzések

- Minden modell soft-delete-es (`default_scope { where(deleted_at: nil) }`); az updater
  `.unscoped`-dal "feltámasztja" az újra beküldött, korábban törölt rekordokat.
- A JSON-formátum szándékosan bug-kompatibilis az egykori Go backenddel
  (Go zero-time timestampek, camelCase kulcsok, legacy flat path mezők).
- Modell-kiterjesztési pontok: `ActiveSupport.on_load(:warp_engine_<model>)` hookok.

## Tesztek

```sh
bundle install
bundle exec rake app:db:prepare RAILS_ENV=test   # warp_engine_test DB a dummy apphoz
bundle exec rspec
```
