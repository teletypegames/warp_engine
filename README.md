# WarpEngine

Mountable Rails engine: a retro software catalog with a CI-pipeline-callable
release updater, a public read-only JSON API, and ActiveAdmin resources that
load into the host application's admin.

> **Development happens in the `tools/teletypegames` monorepo** under
> `libs/ruby/warp_engine`. The standalone `tools/warp_engine` repository is a
> **read-only split mirror** published by CI on every master push — do not
> push to it directly. Tagged releases (`warp_engine-vX.Y.Z`) are also
> published as a gem to the Forgejo rubygems registry
> (`https://git.teletypegames.org/api/packages/tools/rubygems`).

## What it provides

- **Models**: `Software`, `Release`, `ReleaseAsset`, `ExternalLink`,
  `PlatformLink`, `Image`, `SoftwareImage`, `Download` (all under
  `WarpEngine::`, with unprefixed table names)
- **Updater**: `GET /update?platform=&name=&version=` (auth via the
  `X-Update-Secret` header or `?secret=`) — CI copies build artifacts under
  `file_container_path` using the `<name>-<version>*` naming convention, then
  calls the endpoint; the updater extracts archives, parses metadata, and
  upserts the Software/Release/ReleaseAsset/ExternalLink records.
  Supported platforms: tic80, ebitengine, love, c64, godot, bevy, phaser.
- **Public API**: `/api/software`, `/api/software/highlighted`, `/api/builds`,
  `/api/softwares/:name/builds`, `/api/image/:id`, `/api/download?path=`,
  `/file/*path`
- **Admin**: ActiveAdmin resource files (softwares with a 3-level nested form,
  releases, external links, platform links, images with orphan management, a
  Files file-manager page with picker mode, download stats) — loaded into the
  host's single ActiveAdmin instance.

## Installation

```ruby
# Gemfile
gem "warp_engine", path: "../../libs/ruby/warp_engine"
```

```sh
rails g warp_engine:install   # initializer + create_warp_engine_tables migration
rails db:migrate
```

```ruby
# config/routes.rb — keep it the last entry so host routes win
mount WarpEngine::Engine => "/"
```

## Configuration

```ruby
Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    c.file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
    c.image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
    c.update_secret        = ENV["UPDATE_SECRET"] # nil => /update rejects everything
    # If host models also reference catalog images:
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

## Host expectations

- **ActiveAdmin + Devise live in the host**: authentication, theme, assets and
  the `/admin` routes are the host's responsibility; the engine only appends
  its resource files to `ActiveAdmin.application.load_paths`.
- **Files picker JS**: the file-picker next to release-asset path inputs relies
  on a few lines of JS in the host's `active_admin.js` (an iframe pointing at
  `/admin/files?picker=1&field=<dom_id>`) — copy that over to a new host too.
- **apipie**: if the host generates apipie docs, add the engine to the matcher:
  `"#{WarpEngine::Engine.root}/app/controllers/**/*.rb"`.

## Behavioral notes

- Every model is soft-deleted (`default_scope { where(deleted_at: nil) }`);
  the updater "resurrects" re-submitted, previously deleted records via
  `.unscoped`.
- The JSON shape is intentionally bug-compatible with the former Go backend
  (Go zero-time timestamps, camelCase keys, legacy flat path fields).
- Model extension points: `ActiveSupport.on_load(:warp_engine_<model>)` hooks.

## Tests

```sh
bundle install
bundle exec rake app:db:prepare RAILS_ENV=test   # warp_engine_test DB for the dummy app
bundle exec rspec
```
