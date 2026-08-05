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
  box: TIC-80, Ebitengine, LÖVE, C64, Godot, Bevy, Phaser. Authenticated by
  a shared secret or by per-owner database tokens with expiry and scopes
  (`ApplicationToken`, managed in the admin).
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

## Example stack (docker compose)

`examples/compose` boots everything the engine's workflow assumes, end to
end: the catalog app itself, the SSH drop area the updater contract feeds
from and — behind a compose profile — a Gitea forge with Woodpecker CI, so
you can watch a pipeline publish a release into the catalog.

| Service | Role | Where |
| --- | --- | --- |
| `app` | Minimal Rails host with the engine mounted as a path gem (headless: API + updater) | `http://localhost:8080` |
| `mysql` | Catalog database | internal |
| `droparea` | SSH server where pipelines drop build artifacts; shares the `softwares` volume with `app` | `ssh drop@localhost -p 2222` |
| `gitea` | Git forge (profile `ci`) | `http://gitea:3000` |
| `woodpecker` + agent | CI wired to gitea (profile `ci`) | `http://woodpecker:8000` |

### Quickstart — catalog + drop area

```sh
cd examples/compose
cp .env.example .env   # defaults work for a throwaway local demo
docker compose up --build
```

The first boot takes a few minutes: the app container bundles, runs
`rails g warp_engine:install` and `rails db:prepare`, then serves on
`http://localhost:8080`:

- `http://localhost:8080/api/software` — the (empty) catalog
- `http://localhost:8080/api/builds` — the platform build matrix
- `http://localhost:8080/api/docs` — apipie API docs

### Publish a release by hand

The updater contract needs nothing but files in the drop area and one HTTP
call, so you can play the role of the CI pipeline yourself:

```sh
# 1. Fake a build: metadata, a web build and a windows artifact, named by
#    convention (the love platform requires the .html.zip web build)
cat > demo-0.1.0.metadata.json <<'JSON'
{ "name": "demo", "title": "Demo Game", "author": "You", "desc": "Hello", "license": "MIT" }
JSON
echo '<h1>demo</h1>' > index.html && zip demo-0.1.0.html.zip index.html
echo hello > game.bin && zip demo-0.1.0-win-x64.zip game.bin

# 2. Drop them (password: DROP_PASSWORD from .env, default "drop")
scp -P 2222 demo-0.1.0.* drop@localhost:drop/

# 3. Trigger the updater
curl -H "X-Update-Secret: example-update-secret" \
  "http://localhost:8080/update?platform=love&name=demo&version=0.1.0"
```

`GET /api/software` now lists *Demo Game* with `html` and `win_x64` assets,
`http://localhost:8080/file/demo-0.1.0/index.html` serves the extracted web
build, and `GET /api/download?path=demo-0.1.0-win-x64.zip` serves the
artifact while logging a download record.

### Full loop — forge + CI (profile `ci`)

gitea and woodpecker address each other by service name, so let your browser
resolve those names too:

```sh
echo "127.0.0.1 gitea woodpecker" | sudo tee -a /etc/hosts
```

1. `docker compose --profile ci up -d gitea`, open `http://gitea:3000`,
   finish the install wizard (SQLite is fine) and create your admin user.
2. In gitea: *Settings → Applications → Manage OAuth2 Applications*, create
   an app with redirect URI `http://woodpecker:8000/authorize`; copy the
   client id/secret into `WOODPECKER_GITEA_CLIENT` / `WOODPECKER_GITEA_SECRET`
   in `.env`.
3. `docker compose --profile ci up -d` — then log in at
   `http://woodpecker:8000` (OAuth via gitea) and enable your repository.

A pipeline publishes a release exactly like the by-hand steps above — build,
`scp` to `droparea`, call `/update`:

```yaml
# .woodpecker.yaml in a game repo hosted on the example gitea
steps:
  publish:
    image: alpine
    environment:
      DROP_PASSWORD:
        from_secret: drop_password
      UPDATE_SECRET:
        from_secret: update_secret
    commands:
      - apk add --no-cache openssh-client sshpass curl zip
      - # ... build your game, produce mygame-1.0.0.metadata.json + artifacts ...
      - sshpass -p "$DROP_PASSWORD" scp -P 2222 -o StrictHostKeyChecking=no mygame-1.0.0.* drop@droparea:drop/
      - curl -fs -H "X-Update-Secret: $UPDATE_SECRET" "http://app:3000/update?platform=love&name=mygame&version=1.0.0"
```

(The agent attaches pipeline containers to the stack network, so `droparea`
and `app` resolve. For real projects, the per-platform
[`tools/*-tools`](https://git.teletypegames.org) repos ship ready-made
Makefile + pipeline templates implementing this contract.)

Tear the stack down with `docker compose --profile ci down -v`.

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

    # Authentication source for /update — an exclusive choice:
    #   :env      — the shared secret above is accepted (default)
    #   :database — only WarpEngine::ApplicationToken records with the
    #               "update" scope are accepted; the shared secret stops
    #               working the moment you switch.
    # :database mode also requires the owner class every token belongs to:
    # c.application_token_source = :database
    # c.application_token_owner_class = "AdminUser"

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

### Updater authentication

The `X-Update-Secret` header (or the `?secret=` query param) carries one of
two credentials, selected by `application_token_source` — the modes are
exclusive, the endpoint never accepts both:

- **`:env`** (default): the single shared secret from `update_secret`.
- **`:database`**: `WarpEngine::ApplicationToken` records. Each token
  belongs to an owner (the class named by `application_token_owner_class`,
  e.g. `AdminUser`), carries a free-form scope list — `/update` requires the
  `"update"` scope — and an optional expiry. Tokens are created in the admin
  (*App Tokens*): the plain token is generated server-side and shown exactly
  once after creation; only its SHA256 digest is stored. Deleting a token in
  the admin revokes it (soft delete), and `last_used_at` records when each
  token last authenticated successfully.

When switching to `:database`, create the tokens and move your pipelines to
them first — the flip invalidates the shared secret immediately.

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
