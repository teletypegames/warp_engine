# WarpEngine

Mountable Rails engine: retro szoftverkatalógus CI-pipeline-ból hívható release-updaterrel,
publikus read-only JSON API-val és a host adminjába betöltődő ActiveAdmin erőforrásokkal.

## Használat

```ruby
# Gemfile
gem "warp_engine", path: "../../libs/ruby/warp_engine"

# config/routes.rb — utolsó sorként, hogy a host route-jai nyerjenek
mount WarpEngine::Engine => "/"

# config/initializers/warp_engine.rb
WarpEngine.configure do |c|
  c.file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
  c.image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
  c.update_secret        = ENV["UPDATE_SECRET"]
  # Ha a host modelljei is használnak katalógus-képeket:
  c.image_owners << {
    label: "member",
    image_ids: -> { Member.where.not(image_id: nil).distinct.pluck(:image_id) },
    usage_label: ->(image) { "member" if Member.where(image_id: image.id).exists? }
  }
end
```

## Megjegyzések

- A modellek soft-delete-et használnak (`default_scope { where(deleted_at: nil) }`);
  az updater `.unscoped`-dal "feltámasztja" az újra beküldött, korábban törölt rekordokat.
- A táblanevek prefix nélküliek (`softwares`, `releases`, ...).
- Az admin erőforrások a host ActiveAdmin példányába töltődnek be; auth (Devise) a host dolga.
