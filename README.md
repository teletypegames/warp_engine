# WarpEngine

A mountable Rails engine that turns any Rails application into a retro
software catalog: catalog models, a CI-pipeline-callable release updater, a
public read-only JSON API, and optional ActiveAdmin resources that plug into
your app's existing admin.

Repository: `https://git.teletypegames.org/engines/warp_engine`

## Features

- **Catalog domain**: `Software`, `Release`, `ReleaseAsset`, `ExternalLink`,
  `PlatformLink`, `SoftwareImage`, `Download` models with soft-delete
  semantics and download statistics.
- **Platform registry**: `WarpEngine::Platform` is the one place a platform is
  named. `Platform.names` lists them, `Platform.find!("godot")` answers with a
  value object that knows its `label`, its `expected_kinds` and its updater
  `service`. Reference it instead of writing a platform list of your own —
  `PlatformLink::SUPPORTED_PLATFORMS` is kept as an alias of `Platform::NAMES`.
- **Asset checklist**: `rake warp_engine:builds:check` prints, per software and
  release, which release assets exist and which the platform's pipeline could
  still deliver. See *Which assets are missing*.
- **CI-callable updater**: your build pipeline uploads artifacts over HTTP
  and calls one endpoint — WarpEngine extracts archives, parses metadata
  and upserts the catalog records. Supported platforms out of the
  box: TIC-80, Ebitengine, LÖVE, C64, Plus/4, Godot, Bevy, Phaser. Authenticated by
  a shared secret or by per-owner database tokens with expiry and scopes
  (`ApplicationToken`, managed in the admin).
- **Pluggable access**: a host supplies a policy and the catalog gains prices,
  entitlements and gated downloads — and *says so* in its API, so clients can
  show a paid title as paid instead of failing at the download. Default `:open`
  is the catalog as it always was.
- **Client sign-in**: an RFC 8628 device authorization grant for clients with no
  browser of their own, over the host's own user model. Off unless configured.
- **Host-owned image library**: the catalog links a software to its images and
  publishes their URLs, but the image model, its files, its endpoint and its
  admin page belong to the host — the same model can serve avatars or anything
  else the site has (see *Images*).
- **Pluggable storage**: artifacts are served through a storage adapter
  (`:local` by default); a host can serve them from an object store without
  patching the engine.
- **Publish events**: every published release emits
  `ActiveSupport::Notifications` (`warp_engine.publish`), so hosts can react
  to new builds without model callbacks.
- **Public JSON API**: catalog listing, highlighted title, per-platform build
  matrix, download tracking, and a static file server for web-playable builds.
- **Admin (optional)**: if the host runs ActiveAdmin, WarpEngine contributes
  ready-made resources — a catalog editor with nested release/asset forms, a
  file manager with a picker mode, and download statistics. Without ActiveAdmin the engine runs headless
  (API + updater only).
- **Pluggable CI**: pipeline configs, repo sync, build triggers and secret
  provisioning all go through one adapter. Woodpecker ships with the engine
  (`WarpEngine::CI::Woodpecker`) and is the default; `:none` turns CI off, and
  another server is a host-supplied object.

## Requirements

- Rails >= 8.0
- A relational database (developed and tested against MySQL 8)
- Optional: ActiveAdmin + Devise in the host app for the admin UI

## Example stack (docker compose)

`examples/compose` boots everything the engine's workflow assumes, end to
end: the catalog app itself and — behind a compose profile — a Gitea forge
with Woodpecker CI, so you can watch a pipeline publish a release into the
catalog.

| Service | Role | Where |
| --- | --- | --- |
| `app` | Minimal Rails host with the engine mounted as a path gem (headless: API + updater) | `http://localhost:8080` |
| `mysql` | Catalog database | internal |
| `gitea` | Git forge (profile `ci`) | `http://gitea:3000` |
| `woodpecker` + agent | CI wired to gitea (profile `ci`) | `http://woodpecker:8000` |

### Quickstart — catalog only

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

The updater contract is nothing but a handful of HTTP calls, so you can play
the role of the CI pipeline yourself:

```sh
# 1. Fake a build: metadata, a web build and a windows artifact, named by
#    convention (the love platform requires the .html.zip web build)
cat > demo-0.1.0.metadata.json <<'JSON'
{ "name": "demo", "title": "Demo Game", "author": "You", "desc": "Hello", "license": "MIT", "category": "demo" }
JSON
echo '<h1>demo</h1>' > index.html && zip demo-0.1.0.html.zip index.html
echo hello > game.bin && zip demo-0.1.0-win-x64.zip game.bin

# 2. Upload them (one request per file)
for f in demo-0.1.0.*; do
  curl -fs -H "X-Update-Secret: example-update-secret" \
    -F "file=@$f" "http://localhost:8080/build/upload?name=demo&version=0.1.0"
done

# 3. Publish the release
curl -X POST -H "X-Update-Secret: example-update-secret" \
  "http://localhost:8080/build/publish?platform=love&name=demo&version=0.1.0"
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
upload, publish:

```yaml
# .woodpecker.yaml in a game repo hosted on the example gitea
steps:
  publish:
    image: alpine
    environment:
      UPDATE_SECRET:
        from_secret: update_secret
    commands:
      - apk add --no-cache curl zip
      - # ... build your game, produce mygame-1.0.0.metadata.json + artifacts ...
      - for f in mygame-1.0.0.*; do curl -fs -H "X-Update-Secret: $UPDATE_SECRET" -F "file=@$f" "http://app:3000/build/upload?name=mygame&version=1.0.0"; done
      - curl -fs -X POST -H "X-Update-Secret: $UPDATE_SECRET" "http://app:3000/build/publish?platform=love&name=mygame&version=1.0.0"
```

(The agent attaches pipeline containers to the stack network, so `app`
resolves. For real projects, the per-platform
[`tools/*-tools`](https://git.teletypegames.org) repos ship ready-made
Makefile + pipeline templates implementing this contract.)

Tear the stack down with `docker compose --profile ci down -v`.

## Installation

From the git repository:

```ruby
# Gemfile
gem "warp_engine", git: "https://git.teletypegames.org/engines/warp_engine.git"
```

Or from the Forgejo rubygems registry, which is where **tagged releases** land — a
version rather than whatever a branch happens to hold:

```ruby
source "https://git.teletypegames.org/api/packages/engines/rubygems" do
  gem "warp_engine", "~> 0.5"
end
```

The registry is publicly readable, so no credential is needed to install from it. Use a
**block-scoped** source rather than a second global one: with two global sources Bundler
cannot say which gem came from where.

Then:

```sh
rails g warp_engine:install   # initializer, image library (model + endpoint), migrations
rails db:migrate
```

```ruby
# config/routes.rb
namespace :api do
  # The image library is yours; the engine only publishes these URLs.
  get "image/:id", to: "images#show"
end

# keep the mount the last entry so your own routes win
mount WarpEngine::Engine => "/"
```

## Configuration

```ruby
# config/initializers/warp_engine.rb
Rails.application.config.to_prepare do
  WarpEngine.configure do |c|
    # Where CI drops build artifacts
    c.file_container_path = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")

    # Where the site this catalog belongs to lives. The admin links a software
    # to its public page from here; left nil, the link is left out.
    c.site_url = ENV["SITE_URL"]

    # Your image model (see "Images" below). "Image" is the default.
    # c.image_class_name = "Media::Picture"
    # c.image_adapter    = MyImageLibrary.new

    # Shared secret for the /build/* endpoints.
    # nil => the endpoints reject every request.
    c.update_secret = ENV["UPDATE_SECRET"]

    # Authentication source for /build/* — an exclusive choice:
    #   :env      — the shared secret above is accepted (default)
    #   :database — only WarpEngine::ApplicationToken records with the
    #               "update" scope are accepted; the shared secret stops
    #               working the moment you switch.
    # :database mode also requires the owner class every token belongs to:
    # c.application_token_source = :database
    # c.application_token_owner_class = "AdminUser"

    # Size cap for /build/upload and the admin file manager, in bytes (default 500MB).
    # c.max_upload_size = 500 * 1024 * 1024

    # Owner isolation: a database token may only upload/publish softwares
    # owned by its own owner (unrestricted tokens are exempt). Enable only
    # after backfilling owners — ownerless softwares are claimable by anyone.
    # c.enforce_software_ownership = true

    # Which CI server builds the games (see "CI" below). :woodpecker (default)
    # reads WOODPECKER_URL / WOODPECKER_API_TOKEN from the environment; naming
    # the adapter is better, because then the settings are here in the open.
    # c.ci_adapter = WarpEngine::CI::Woodpecker::Adapter.new(
    #   url: ENV["WOODPECKER_URL"], api_token: ENV["WOODPECKER_API_TOKEN"],
    #   platforms: { "godot" => { builder: "registry.example/godot-builder:4.6" } }
    # )
    # c.ci_adapter = :none   # this host builds nothing

    # Who may see a title and who may download it (see "Access" below).
    # :open (default) lists everything and serves everything.
    # c.access_policy = MyStore::AccessPolicy.new

    # Client sign-in (see "Client sign-in" below). nil (default) means there is
    # none: /api/auth/* answers 404 and GET /api/service reports auth: null.
    # c.access_token_owner_class  = "User"
    # c.identity_verification_url = "/devices"
    #
    # How to recognise a caller with a session instead of a bearer token.
    # c.subject_resolver = ->(request) { request.env["warden"]&.user }

    # How big a catalog page is when a client asks for one without saying, and the
    # most it may ask for (see "Paging and filters").
    # c.catalog_page_size     = 48
    # c.catalog_max_page_size = 200
  end
end
```

## The updater contract

Publishing a release from CI is two steps:

1. **Upload** build artifacts into `file_container_path`, named by convention:
   `<name>-<version>.metadata.json`, `<name>-<version>.html.zip`,
   `<name>-<version>-win-x64.zip`, `<name>-<version>.tic`, ... (each platform
   declares which asset kinds it expects — see `GET /api/builds`). Push them
   over HTTP — one request per file, `upload` scope, optional `sha256`
   integrity check:

   ```sh
   curl -H "X-Update-Secret: $UPDATE_SECRET" \
     -F "file=@mygame-1.2.0.html.zip" \
     "https://your-host/build/upload?name=mygame&version=1.2.0"
   ```

2. **Publish the release**:

   ```sh
   curl -X POST -H "X-Update-Secret: $UPDATE_SECRET" \
     "https://your-host/build/publish?platform=tic80&name=mygame&version=1.2.0"
   ```

The metadata file (`<name>-<version>.metadata.json`, or the `-- key: value` header of
a TIC-80 cartridge's source) is what fills the `Software` record: `name`, `title`,
`author`, `desc`, `license`, and optionally `site` and `repo`, which become external
links, and `category` — a key a client may group titles by (`puzzle`, `action`,
`demo`). Every key is optional but `name`; an absent `category` is `null` in the API
and a client draws no category axis until a catalog publishes one.

**Statuses and categories are a vocabulary in the database**, not a list in the code:
`WarpEngine::SoftwareStatus` (key, label, position, `default_visible`, `badge`) and
`WarpEngine::SoftwareCategory` (key, label, position, `needs_review`), both editable in
the admin and published by `GET /api/software/vocabulary`. A software's `status` must be
a known key — the migration seeds `released`, `demo`, `development` and `archived`. A
category a publish brings that nobody has named yet is **not an error**: it is added to
the vocabulary with its key as its label and `needs_review` set, for the admin to name.
A database that got its tables from `db:schema:load` rather than the migration — a test
database, a fresh install — has no status rows; the model seeds the four the first time
anything asks, so nothing depends on the migration having run.

WarpEngine extracts the archives, parses the metadata (JSON, or the Lua
comment header for TIC-80), and upserts the `Software`, `ExternalLink`,
`Release` and `ReleaseAsset` records in a single transaction. Previously
deleted records are resurrected on re-ingest.

### Updater authentication

The `X-Update-Secret` header carries one of two credentials, selected by
`application_token_source` — the modes are exclusive, the endpoint never
accepts both:

- **`:env`** (default): the single shared secret from `update_secret`.
- **`:database`**: `WarpEngine::ApplicationToken` records. Each token
  belongs to an owner (the class named by `application_token_owner_class`,
  e.g. `AdminUser`), carries a free-form scope list — publishing requires
  the `"update"` scope, `/build/upload` the `"upload"` scope — and an
  optional expiry. Tokens are created in the admin
  (*App Tokens*): the plain token is generated server-side and shown exactly
  once after creation; only its SHA256 digest is stored. Deleting a token in
  the admin revokes it (soft delete), and `last_used_at` records when each
  token last authenticated successfully.

When switching to `:database`, create the tokens and move your pipelines to
them first — the flip invalidates the shared secret immediately.

## Which assets are missing (rake)

A release is complete when it carries every asset kind its platform can
produce. Nothing enforces that — a pipeline step can fail, a platform can gain
a target, a title can be published from a laptop — so the engine ships a
checklist:

```
$ bin/rails warp_engine:builds:check

WarpEngine release asset coverage — latest release per software
expected: the kinds a platform's updater registers · [ ] the CI builds it · [-] the CI does not, upload it by hand

rabbitroller  ebitengine  v1.1.1  3/7
  [x] html
  [x] win_x64
  [x] linux_x64
  [ ] win_x86
  [ ] linux_arm64
  [-] mac_x64
  [-] mac_arm64

The CI can build these and the release does not have them:
  rabbitroller v1.1.1 (ebitengine): win_x86, linux_arm64

12 softwares, 12 releases, 61/78 assets present, 11 missing from CI-built kinds
4 softwares are missing an asset the CI builds
2 assets are expected but this CI does not build them
```

Three markers, three different facts:

| Marker | Meaning |
| --- | --- |
| `[x]` | the release has this asset |
| `[ ]` | the platform expects it **and** the CI pipeline builds it — a real gap |
| `[-]` | the platform expects it but this CI cannot build it (ebitengine's macOS targets need osxcross) — a manual upload, or nothing |
| `[+]` | the release has an asset the platform does not expect |

The expectations come from two places, and the difference is the point:
`WarpEngine::Platform#expected_kinds` is what the **updater** can ingest, and
the CI adapter's `built_kinds(platform)` is what the **pipeline** produces. An
adapter that cannot answer (no CI configured, or a platform with no builder)
returns nil, and then nothing is excused: every missing kind is reported as a
gap.

Options are environment variables, so the task composes in a shell:

| Variable | Effect |
| --- | --- |
| `NAME=rabbitroller` | one software |
| `PLATFORM=ebitengine` | one platform |
| `RELEASES=all` | every release, not just the newest one per software |
| `ONLY=missing` | only the releases that are short of a CI-built asset |
| `STRICT=1` | exit non-zero when anything is missing (for CI) |

The newest release is the newest non-`dev-` version, the same rule the catalog
API uses when it names a title's latest release.

The same numbers are available as objects: `WarpEngine::AssetCoverage.new(...)`
answers `#rows`, `#missing_rows` and `#totals`, and
`WarpEngine::AssetCoverageChecklist` is what renders them.

## CI

Every CI feature — serving pipeline configs, syncing repositories, triggering
builds, provisioning secrets — goes through **one adapter**. Woodpecker ships
with the engine as `WarpEngine::CI::Woodpecker`, and it is the default:

```ruby
# nothing set: Woodpecker, configured from ENV, exactly as before
c.ci_adapter = :woodpecker

# named explicitly (recommended — the host says what its CI is)
c.ci_adapter = WarpEngine::CI::Woodpecker::Adapter.new(
  url:            ENV["WOODPECKER_URL"],
  api_token:      ENV["WOODPECKER_API_TOKEN"],
  repo_owner:     ENV["WOODPECKER_REPO_OWNER"],
  public_key_url: "https://ci.example.org/api/signature/public-key",
  update_server:  "https://catalog.example.org",
  platforms:      { "godot" => { builder: "registry.example/godot-builder:4.6" } }
)

# this host builds nothing: /api/ci/* answers 503, /build/config refuses,
# and the admin pipeline actions hide themselves
c.ci_adapter = :none
```

The engine's own code never names a provider: `WarpEngine.ci` is the adapter,
`WarpEngine::CI::Repo` and `WarpEngine::CI::Run` are what it hands back, and
`WarpEngine::CI::ConnectionError` / `ApiError` / `NotConfigured` are what it
raises. A host with a different CI server implements this contract instead:

| Method | Purpose |
| --- | --- |
| `name` | provider label, shown in the admin |
| `configured?` | false keeps every CI feature inactive |
| `platforms` | which platforms `/build/config` can serve |
| `update_server` | server URL written into the generated pipeline; nil = the request's base_url |
| `repos`, `repo(id)` | `CI::Repo` values for the repo sync |
| `activate_repo(id)`, `deactivate_repo(id)` | enable/disable a repository |
| `runs(repo_id, page:)`, `run(repo_id, number)` | `CI::Run` values (`number` may be `"latest"`) |
| `trigger(repo_id, branch:)` | start a build, returns a `CI::Run` |
| `secret_names(repo_id)`, `secret_set(repo_id, name:, value:)`, `secret_delete(repo_id, name)` | token provisioning |
| `verify_config_request(request)` | is this really the CI server calling |
| `config_marker(params)` | `{ platform:, name: }` from the request, or nil for "not ours" |
| `pipeline_config(platform:, name:, update_server:)` | the pipeline definition, or nil for an unknown platform |
| `config_response(platform:, config:)` | the body the CI server expects |

`Pipeline` records keep the provider-neutral `remote_repo_id` reader over the
historical `woodpecker_repo_id` column, so the table did not have to move.

### Pipeline configs (the Woodpecker adapter)

WarpEngine can act as a [Woodpecker configuration extension](https://woodpecker-ci.org/docs/usage/extensions/configuration-extension):
instead of a copy-pasted `.woodpecker.yaml` in every game repo, the repo holds a
one-line marker and the engine serves the full per-platform pipeline
(version → build → upload → publish, calling `/build/upload` + `/build/publish`
with the `application_token` Woodpecker secret):

```yaml
# .woodpecker.yaml in a game repo
platform: godot
```

- `POST /build/config` — the extension endpoint Woodpecker calls on every
  pipeline start (httpsig/ed25519-signed request, verified against the
  adapter's `public_key` / `public_key_url`). Non-marker configs get a `204` so the
  repo's own YAML keeps running — opt-in migration, and putting a full
  pipeline back into the repo is the opt-out.
- `GET /build/config?platform=godot` — renders the same pipeline as a preview.

The adapter's `platforms` maps platform names to builder images
(`{ "godot" => { builder: "..." }, "c64" => { builder: ..., exporter: ... } }`);
`exporter` is a second image a template may run a step in — the c64 and plus4
pipelines package the `.prg` into the browser player and the native players
there — and an empty map (default) disables the feature. Set the Woodpecker side with
`WOODPECKER_CONFIG_EXTENSION_ENDPOINT=https://your-host/build/config` (or
per-repo in Settings → Extensions). Templates live with the adapter, in
`lib/warp_engine/ci/woodpecker/platforms/<platform>/pipeline.yaml.erb` — the
YAML dialect belongs to the provider, so a second adapter brings its own.

### CI management (the Woodpecker adapter)

Beyond serving pipeline configs, the adapter drives the Woodpecker REST API
itself. Give it a `url` and an `api_token` — with either missing, `configured?`
is false, every management feature stays inactive and the admin pages hide
themselves.

What it unlocks (all surfaced in the admin):

- **Repo sync** (*Pipelines → Sync from …*): mirrors the provider's
  repo list into `Pipeline` records, auto-matching each repo to a catalog
  `Software` by name; repos that disappear from Woodpecker are deactivated.
  Platform and software links are editable by hand afterwards.
- **Pipeline history**: each entry on the *Pipelines* page lists its recent
  runs with a manual *Trigger* action; the newest run refreshes the cached
  last-pipeline status shown on the Pipelines index. The software's admin
  page links to its pipelines from the Quick Links sidebar.
- **Secret provisioning**: database application tokens are pushed to the
  repos as the `application_token` CI secret — creating a token
  provisions it to its owner's repos (unrestricted tokens to all active
  repos), deleting a token removes the secret, and *Rotate* creates a
  replacement token, provisions it everywhere and revokes the old one in a
  single step.

The API token must belong to a Woodpecker **instance admin** — listing the
server's repos is an admin-only endpoint (anything less yields
`403 User not authorized`). Add the user to `WOODPECKER_ADMIN` on the
Woodpecker server, then log out and back in: the admin flag is written to
the user record at login, a server restart alone is not enough.

## Storage

Build artifacts are served through a storage adapter. The default is the
local filesystem under `file_container_path` — byte for byte the behaviour
the engine always had:

```ruby
c.storage_adapter = :local   # default
```

A host that keeps its artifacts elsewhere (an object store behind a CDN, for
example) can plug in its own object instead of patching the engine. The
contract is three methods:

```ruby
class MyObjectStore
  def file?(relative_path)      = ...   # true/false
  def directory?(relative_path) = ...   # true/false

  # Return a WarpEngine::Storage::Location:
  #   Location.file(absolute_path)  — the engine will send_file it
  #   Location.redirect(url)        — the engine will redirect (signed URL)
  def locate(relative_path, filename: nil, expires_in: nil) = ...
end

c.storage_adapter = MyObjectStore.new
```

`GET /api/download` and `GET /file/*` both go through the adapter, so a
signing adapter turns them into redirects without any further change.
`WarpEngine::DownloadService#create` still returns an absolute path (and
`nil` when there is none), so existing callers keep working;
`#locate` is the new entry point that can also hand back a redirect.

**Serving only.** Ingestion — `POST /build/upload`, archive extraction and
the admin file manager — still writes to the local disk. A remote adapter
needs its own upload path today.

## Images

An image is not a catalog concept: the same picture library serves covers,
screenshots, avatars and whatever else a site has. So the engine owns only the
link — `SoftwareImage`, ordered, with one default — while the `Image` model, the
uploaded files and the admin page live in the host. `rails g warp_engine:install`
writes a working one (`app/models/image.rb`, `app/controllers/api/images_controller.rb`,
a `create_images` migration); the engine talks to it through an adapter:

```ruby
c.image_class_name = "Image"   # default
```

The default adapter expects that model to answer `original_filename`,
`content_type`, `file_path` and `file_upload=` (the generated one does), and
publishes every image as `/api/image/<id>` — the address clients have always
used, which is why the generated route serves exactly that. A host that keeps
its pictures somewhere else replaces the adapter instead:

```ruby
class MyImageLibrary
  def model_name                = "Media::Picture"
  def model                     = Media::Picture
  def url_for(image_id)         = "https://cdn.example.com/#{image_id}.webp"
  def build_from_upload(upload) = Media::Picture.new(file_upload: upload)
  def label_for(record)         = record.title
  def available?(record)        = record.stored?
  def select_options            = Media::Picture.order(:title).pluck(:title, :id)
end

c.image_adapter = MyImageLibrary.new
```

`url_for` is what lands in the catalog JSON (`imageUrl`, `images[].url`) and in
the admin previews; `select_options` fills the image picker on the software
form; `build_from_upload` is what "upload a new image" on that form calls.

**The `images` table stays where it is.** Moving the model out of the engine did
not touch it: the engine no longer creates it (the install generator does, as
host code), and `software_images.image_id` still points at the same rows.

## Access

Who may see a title, and who may download it. The default answers "everyone" to
both — every software listed, every artifact served, no prices — which is the
catalog the engine always had:

```ruby
c.access_policy = :open   # default
```

A host that sells supplies a policy instead. The contract is three methods:

```ruby
class MyStore::AccessPolicy
  # Which titles GET /api/software lists at all.
  def visible_software_scope(subject: nil) = ...   # an ActiveRecord scope

  # What a client is told about one title.
  def access_for(software:, subject: nil)
    WarpEngine::Access.new(
      gated: true, entitled: false,           # needs an entitlement; this caller has none
      price_cents: 1490, currency: "EUR",
      purchase_url: "https://shop.example/games/slug",
      web_url: "https://shop.example/play/slug"   # nil keeps the engine's own /file/ path
    )
  end

  # nil refuses the download; a Grant allows it.
  def authorize_download(asset:, subject:, request:) = WarpEngine::Access::Grant.new
end

c.access_policy = MyStore::AccessPolicy.new
```

`subject` is whoever the request authenticated as, or `nil` for an anonymous
caller — deliberately untyped, because the engine has no user model and whose
object this is belongs to the host.

Every catalog entry carries an `access` block, **including under the open
policy**, so a client never has to tell "this catalog says nothing" from "this
title is not gated":

```json
"access": { "gated": false, "entitled": true, "price": null,
            "purchaseUrl": null, "webUrl": null }
```

The vocabulary is generic on purpose. A client reads more than one store, and a
word from any one host's domain would make it specific to that host.

**A policy that raises is treated as a refusal**: an empty catalog and a denied
download, logged. An artifact served because the gatekeeper crashed is the one
failure mode this engine must not have.

## Client sign-in

A desktop client has no cookie jar and no browser session, so it cannot host a
login form without asking somebody to type a password into a window that is not
a browser. The engine implements the device authorization grant (RFC 8628)
instead — but only where a host has said whose tokens these are:

```ruby
c.access_token_owner_class  = "User"      # nil (default): no sign-in at all
c.identity_verification_url = "/devices"  # your page where a person types the code
c.device_code_ttl           = 600
c.device_code_interval      = 5
```

With `access_token_owner_class` unset, `/api/auth/*` answers 404 and
`GET /api/service` reports `auth: null`, so a client offers no sign-in.

The flow:

1. the client `POST`s `/api/auth/device` and shows the `userCode` it gets back;
2. the person opens `verificationUrl` in a browser and types that code;
3. **your page** calls `WarpEngine::DeviceGrantService#approve(user_code:, subject:)`
   with the signed-in user — approving needs a session and HTML, neither of
   which is the engine's business;
4. the client's next `POST /api/auth/device/token` carries the token away. It is
   handed over exactly once and never stored in the clear afterwards.

### Recognising a browser

A bearer token is what a *client* carries; a browser carries a session, and the
engine has no idea what a session is. A host that wants its signed-in visitors
recognised on these endpoints too — so that clicking a download link on the site
works the same way the client's download does — says how:

```ruby
c.subject_resolver = ->(request) { request.env["warden"]&.user }
```

Without one, a request with no bearer token is anonymous, which is what the
read-only API always did. A resolver that raises is logged and treated as
anonymous rather than taking the request down with it.

The token is a `WarpEngine::ApplicationToken` with the `catalog` scope, sent as
`Authorization: Bearer …`. `DELETE /api/auth/token` revokes it (signing out),
and the admin lists both kinds of token and the sign-ins behind them.

## Publish events

Publishing a release emits an `ActiveSupport::Notifications` event, so a host
can react to a new build without hanging a callback on the models:

```ruby
ActiveSupport::Notifications.subscribe("warp_engine.publish") do |*, payload|
  payload[:software]  # WarpEngine::Software
  payload[:release]   # WarpEngine::Release
  payload[:platform]  # "godot"
  payload[:name]      # "mygame"
  payload[:version]   # "1.2.0"
end
```

Hosts that must support older engine versions can feature-detect with
`WarpEngine.respond_to?(:instruments_publish?) && WarpEngine.instruments_publish?`.

Downloads emit one too — `warp_engine.download`, with `path`, `asset`,
`release`, `software`, `subject` and the `Download` record — so a host can keep
its own account of who fetched what without reaching into `DownloadService`.

## Public API

| Endpoint | Purpose |
| --- | --- |
| `GET /api/service` | What this deployment is: version, whether the catalog gates, and how to sign in (or that you cannot) |
| `GET /api/software` | The catalog with releases, assets, links, download counts, an optional `category` and an `access` block — whole, or one page at a time; see *Paging and filters* |
| `GET /api/software/facets` | How many softwares each status, platform and category would show under the other filters |
| `GET /api/software/vocabulary` | The statuses and categories this catalog uses, with labels and display order |
| `GET /api/software/highlighted` | The currently highlighted title |
| `GET /api/builds` | Expected asset kinds per platform (build matrix) |
| `GET /api/softwares/:name/builds` | Actual vs. missing build assets per release |
| `GET /api/image/:id` | Serves images — **the host's endpoint**, see *Images* |
| `GET /api/download?path=` | Serves an artifact and logs a download record |
| `GET /file/*path` | Serves static build output (web-playable games, docs) |
| `POST /api/auth/device` | Starts a device sign-in; returns the code pair (404 without a client identity) |
| `POST /api/auth/device/token` | Polls a device sign-in for its token |
| `DELETE /api/auth/token` | Revokes the bearer token on the request (signing out) |

Every read endpoint accepts an optional `Authorization: Bearer …`; none requires
one. What it changes is what the access policy is asked about — an anonymous
caller is a normal, supported caller.

### Paging and filters

`GET /api/software` answers in an envelope:

```json
{ "api": 2, "page": 1, "perPage": 48, "total": 131, "totalPages": 3, "nextPage": 2,
  "softwares": [ { "software": { ... }, "releases": [ ... ], "access": { ... } } ] }
```

`api` is the shape version of the JSON (`WarpEngine::API_VERSION`), separate from the
engine's version: it changes when the shape does, and a cached copy carries it where a
response header cannot follow. **Without `page` the whole catalog comes back** in that
envelope, which is what every reader before API version 2 finds under `softwares`; with
`page` (from 1) it is one page of `per_page` entries — `catalog_page_size` when unsaid,
never more than `catalog_max_page_size` — and `nextPage` is null on the last one.

Filters narrow the catalog before it is paged: `status=released,demo`, `platform=c64`,
`category=puzzle`, `q=ra` (title and name), `owner_id=7`; `sort` is `title` (default),
`updated` or `newest`. `/api/software/facets` takes the same filters and answers how many
softwares each value would show given the *other* filters, and `/api/software/vocabulary`
says what the status and category keys mean.

### `WarpEngine-Version`

Every response above carries the engine's version in a `WarpEngine-Version` header, so a
client can branch on the engine's age without a round trip to ask:

```
$ curl -sI https://teletypegames.org/api/software | grep -i warpengine
WarpEngine-Version: 0.5.0
```

Set before the action runs rather than after, which means an error response carries it
too — a client needs the version most when something came back wrong. The name is
`WarpEngine::VERSION_HEADER`, so nothing spells it out twice.

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
- **A software has one pipeline, and the newest assignment wins.** `Software#pipeline` is
  a `has_one`, so two pipelines pointing at the same software is not an error the database
  catches — it is a link that silently does nothing, with the software still showing
  whichever row came first. Assigning a software that another pipeline holds therefore
  *moves* it: the previous holder is left without one, the admin says which one it took it
  from, and `Pipeline#software_taken_from` carries that list for anything else that cares.
  Deliberately a callback rather than a unique index: rows here are soft-deleted, and a
  unique index counts deleted rows, so a pipeline removed last year would block its
  software from ever being linked again.

## Tests

The engine ships an RSpec suite running against a bundled dummy app:

```sh
bundle install
bundle exec rake app:db:prepare RAILS_ENV=test
bundle exec rspec
```

## Development

This repository is a **read-only split mirror** — development happens in the
[`services/teletypegames`](https://git.teletypegames.org/services/teletypegames)
monorepo under `libs/ruby/warp_engine`, and CI republishes the mirror on every
change. Please do not open pull requests against the mirror.

Two rules the monorepo's pipeline enforces before anything is mirrored or
published:

- **Every commit that touches the engine raises `WarpEngine::VERSION`.** A
  pre-commit hook checks it locally, the pipeline's first step checks it again
  over the pushed commits, and a `warp_engine-v*` tag must name the version the
  tree actually holds.
- **RuboCop is green** (`.rubocop.yml`, rubocop-rails-omakase), and the suite
  passes — in that order, before the gem is built.
