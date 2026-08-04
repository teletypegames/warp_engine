# WarpEngine

A mountable Rails engine that turns any Rails application into a retro
software catalog: catalog models, a CI-pipeline-callable release updater, a
public read-only JSON API, and optional ActiveAdmin resources that plug into
your app's existing admin.

Repository: `https://git.teletypegames.org/tools/warp_engine`

## Features

- **Catalog domain**: `Software`, `Release`, `ReleaseAsset`, `ExternalLink`,
  `PlatformLink`, `Image`, `SoftwareImage`, `Download` models with soft-delete
  semantics and download statistics.
- **CI-callable updater**: your build pipeline drops artifacts into a
  directory and calls one endpoint — WarpEngine extracts archives, parses
  metadata and upserts the catalog records. Supported platforms out of the
  box: TIC-80, Ebitengine, LÖVE, C64, Godot, Bevy, Phaser.
- **Public JSON API**: catalog listing, highlighted title, per-platform build
  matrix, image serving, download tracking, and a static file server for
  web-playable builds.
- **Admin (optional)**: if the host runs ActiveAdmin, WarpEngine contributes
  ready-made resources — a catalog editor with nested release/asset forms, an
  image library with orphan cleanup, a file manager with a picker mode, and
  download statistics. Without ActiveAdmin the engine runs headless
  (API + updater only).

## Requirements

- Rails >= 8.0
- A relational database (developed and tested against MySQL 8)
- Optional: ActiveAdmin + Devise in the host app for the admin UI

## Installation

From the git repository:

```ruby
# Gemfile
gem "warp_engine", git: "https://git.teletypegames.org/tools/warp_engine.git"
```

Or from the Forgejo rubygems registry (tagged releases):

```ruby
source "https://git.teletypegames.org/api/packages/tools/rubygems" do
  gem "warp_engine"
end
```

Then:

```sh
rails g warp_engine:install   # initializer + create_warp_engine_tables migration
rails db:migrate
```

```ruby
# config/routes.rb — keep it the last entry so your own routes win
mount WarpEngine::Engine => "/"
```

## Configuration

```ruby
# config/initializers/warp_engine.rb
Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    # Where CI drops build artifacts and where images are stored
    c.file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
    c.image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")

    # Shared secret for the /update endpoint.
    # nil => the endpoint rejects every request.
    c.update_secret = ENV["UPDATE_SECRET"]

    # If your app's own models reference catalog images, register them so the
    # admin Images page counts them as "in use":
    # c.image_owners = [
    #   {
    #     label: "member",
    #     image_ids: -> { Member.where.not(image_id: nil).distinct.pluck(:image_id) },
    #     usage_label: ->(image) { "member" if Member.where(image_id: image.id).exists? }
    #   }
    # ]
  end
end
```

## The updater contract

Publishing a release from CI is two steps:

1. **Upload** build artifacts into `file_container_path`, named by convention:
   `<name>-<version>.metadata.json`, `<name>-<version>.html.zip`,
   `<name>-<version>-win-x64.zip`, `<name>-<version>.tic`, ... (each platform
   declares which asset kinds it expects — see `GET /api/builds`).
2. **Call the endpoint**:

   ```sh
   curl -H "X-Update-Secret: $UPDATE_SECRET" \
     "https://your-host/update?platform=tic80&name=mygame&version=1.2.0"
   ```

WarpEngine extracts the archives, parses the metadata (JSON, or the Lua
comment header for TIC-80), and upserts the `Software`, `ExternalLink`,
`Release` and `ReleaseAsset` records in a single transaction. Previously
deleted records are resurrected on re-ingest.

## Public API

| Endpoint | Purpose |
| --- | --- |
| `GET /api/software` | Full catalog with releases, assets, links, download counts |
| `GET /api/software/highlighted` | The currently highlighted title |
| `GET /api/builds` | Expected asset kinds per platform (build matrix) |
| `GET /api/softwares/:name/builds` | Actual vs. missing build assets per release |
| `GET /api/image/:id` | Serves catalog images |
| `GET /api/download?path=` | Serves an artifact and logs a download record |
| `GET /file/*path` | Serves static build output (web-playable games, docs) |

## Admin integration

The host owns the single ActiveAdmin instance — authentication (Devise),
theme, assets and the `/admin` routes. WarpEngine only appends its resource
files to `ActiveAdmin.application.load_paths`. Two things to copy into a new
host:

- the small file-picker JS for release-asset path inputs (an iframe pointing
  at `/admin/files?picker=1&field=<dom_id>`) in your `active_admin.js`;
- if you generate apipie docs, add
  `"#{WarpEngine::Engine.root}/app/controllers/**/*.rb"` to your
  `api_controllers_matcher`.

## Behavioral notes

- Every model is soft-deleted (`default_scope { where(deleted_at: nil) }`).
- The JSON shape is stable and intentionally bug-compatible with the project's
  former Go backend (Go zero-time timestamps, camelCase keys, legacy flat
  path fields).
- Model extension points: `ActiveSupport.on_load(:warp_engine_<model>)` hooks.

## Tests

The engine ships an RSpec suite running against a bundled dummy app:

```sh
bundle install
bundle exec rake app:db:prepare RAILS_ENV=test
bundle exec rspec
```

## Development

This repository is a **read-only split mirror** — development happens in the
[`tools/teletypegames`](https://git.teletypegames.org/tools/teletypegames)
monorepo under `libs/ruby/warp_engine`, and CI republishes the mirror on every
change. Please do not open pull requests against the mirror.
