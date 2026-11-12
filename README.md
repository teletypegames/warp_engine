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
- **Outlets (1.11)**: the formats the catalog leaves the engine in, side by side —
  the JSON API, shelves and an Assembly64 server — over one shared decision of what
  is on offer (`WarpEngine::Catalog::Offer`), with room for types of the host's own.
  See *Outlets*.
- **Shelves (optional, 1.2)**: a platform's latest public builds as a flat,
  versionless folder with a plain-text `INDEX.TXT`, kept up to date by the engine
  itself — for clients too small to speak JSON over HTTPS (a C64 reading it over
  FTP). Off unless configured.
- **Assembly64 (optional, 1.11)**: the catalog as an Assembly64 search server, so a
  C64 Ultimate finds and runs its titles from the menu. Off unless configured.
- **Publish events**: every published release emits
  `ActiveSupport::Notifications` (`warp_engine.publish`), so hosts can react
  to new builds without model callbacks.
- **Public JSON API**: catalog listing, highlighted title, per-platform build
  matrix, download tracking, and a static file server for web-playable builds.
- **Admin (optional)**: if the host runs ActiveAdmin, WarpEngine contributes
  ready-made resources — a catalog editor with nested release/asset forms, a
  file manager with a picker mode, and download statistics. Without ActiveAdmin the engine runs headless
  (API + updater only).
- **Admin API (optional, 1.0)**: everything the admin does, as a JSON API under
  `/api/admin/v1`, turned on in the initializer, described by a live OpenAPI 3.1
  document and served to LLM agents as an MCP server. Off unless configured.
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

The initializer is a block without a parameter; each line names one setting.
Everything below is optional.

```ruby
# config/initializers/warp_engine.rb
Rails.application.config.to_prepare do
  WarpEngine.configure do
    # Where CI drops build artifacts
    file_container_path ENV.fetch("FILE_CONTAINER_PATH", "/softwares")

    # Where the site this catalog belongs to lives. The admin links a software
    # to its public page from here; left nil, the link is left out.
    site_url ENV["SITE_URL"]

    # Your image model (see "Images" below). "Image" is the default.
    # image_class "Media::Picture"
    # image_adapter MyImageLibrary.new

    # Shared secret for the /build/* endpoints.
    # nil => the endpoints reject every request.
    update_secret ENV["UPDATE_SECRET"]

    # Authentication source for /build/* — an exclusive choice:
    #   :env      — the shared secret above is accepted (default)
    #   :database — only WarpEngine::ApplicationToken records with the
    #               "update" scope are accepted; the shared secret stops
    #               working the moment you switch.
    # :database mode also requires the owner class every token belongs to:
    # application_tokens from: :database, owner: "AdminUser"

    # Size cap for /build/upload and the admin file manager, in bytes (default 500MB).
    # max_upload_size 500 * 1024 * 1024

    # Owner isolation: a database token may only upload/publish softwares
    # owned by its own owner (unrestricted tokens are exempt). Enable only
    # after backfilling owners — ownerless softwares are claimable by anyone.
    # enforce_software_ownership true

    # User agents whose downloads the statistics leave out ("*" matches anything).
    # ignore_user_agents "warpstore/*"

    # Which CI server builds the games (see "CI" below). Without this line it is
    # Woodpecker, configured from WOODPECKER_URL / WOODPECKER_API_TOKEN; naming
    # it is better, because then the settings are here in the open.
    # ci :woodpecker do
    #   url       ENV["WOODPECKER_URL"]
    #   api_token ENV["WOODPECKER_API_TOKEN"]
    #   platform :godot, builder: "registry.example/godot-builder:4.6"
    #   platform :dos,   builder: "registry.example/dos-builder:latest", forge_release: true
    # end
    # ci :none   # this host builds nothing

    # Who may see a title and who may download it (see "Access" below).
    # :open (default) lists everything and serves everything.
    # access_policy MyStore::AccessPolicy.new

    # Client sign-in (see "Client sign-in" below). nil (default) means there is
    # none: /api/auth/* answers 404 and GET /api/service reports auth: null.
    # access_token_owner_class  "User"
    # identity_verification_url "/devices"
    #
    # How to recognise a caller with a session instead of a bearer token.
    # subject_resolver { |request| request.env["warden"]&.user }

    # How big a catalog page is when a client asks for one without saying, and the
    # most it may ask for (see "Paging and filters").
    # catalog_page_size     48
    # catalog_max_page_size 200

    # Flat, versionless copies of a platform's latest builds (see "Shelves").
    # None by default.
    # shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16
  end
end
```

An unknown setting stops the boot with a `NoMethodError`, an unknown shelf, CI or
platform key with an `ArgumentError`. `to_prepare` runs the block again on every
code reload; a shelf (by path), an additional resource (by subject and association)
and a platform (by name) replace their earlier selves instead of adding up.

The block may also take the configuration as a parameter and set its attributes
— `WarpEngine.configure { |c| c.site_url = ENV["SITE_URL"] }`, the form before 1.8.
Both write the same `WarpEngine.config`, and the attribute names are the ones the
sections below mention.

## Host records on a catalog page

The engine owns the catalog; everything else a site wants to keep next to a
software — SEO metadata, notes, legal text, translations — belongs to the host.
`additional_resources` lets the host put its own fields on the engine's admin
page for a software without the engine knowing what they are:

```ruby
# The association is the host's; the engine's models all run a load hook.
ActiveSupport.on_load(:warp_engine_software) do
  has_many :seo_metadata, as: :subject, class_name: "Seo::Metadata", dependent: :destroy

  accepts_nested_attributes_for :seo_metadata, allow_destroy: true
end

WarpEngine.configure do
  # the association above, on the engine resource it hangs on, under a fieldset title;
  # multiple: false for a has_one
  additional_resource :seo_metadata, on: :software, label: "SEO", multiple: true do
    permit :id, :locale, :title, :description, :og_type, :_destroy

    form do |f|
      f.input :locale
      f.input :title
    end
  end
end
```

The engine adds the `permit`ted attributes to the software form's strong parameters
and renders `form` in a fieldset of its own. It never loads the host's class, so
none (the default) leaves the admin page exactly as it was.

Give it an `api_schema` and it also appears in the Admin API, at
`/api/admin/v1/softwares/{id}/extras/{association}`:

```ruby
api_schema do
  integer :id
  string  :locale, enum: %w[en hu]
  string  :title, :description, :og_type, null: true   # ["string", "null"]
end
```

The schema describes one entry: an object whose properties carry the attribute
names in camelCase (`ogType`), as the API writes them. `string`, `integer`,
`number`, `boolean`, `array` and `object` take any number of names; `null: true`
lets a property be null (its `enum` gets a `nil`), and every other option goes
into the property as it is (`format: "date-time"`). A ready OpenAPI Schema Object
works too: `api_schema({ type: "object", ... })`. Without an `api_serializer`
(a block that gets the record) the permitted attributes are written in camelCase.

`config.additional_resources` holds the `WarpEngine::AdditionalResource`s these
lines build; the class takes the same settings as keywords (`subject:`,
`association:`, `label:`, `multiple:`, `permitted:`, `fields:`, `api_schema:`,
`api_serializer:`).

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
and a client draws no category axis until a catalog publishes one. `shelf_name` names the
title's file on a shelf (see *Shelves*); a publish without it keeps the one set in the admin.

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

**Each kind is required, expected or optional on its platform.** A *required* kind
must be uploaded, or the publish answers `422` with the missing kinds and records
nothing: the `cartridge` on tic80, c64, plus4 and dos, the `html` build elsewhere.
Every other kind the platform registers is *expected*: a publish without it goes
through, and the checklist below reports it missing. An *optional* kind may be absent
for good (DOS's `win_x86`, the Win32 build only some programs have) and is not
counted as missing. `GET /api/builds` lists all three per platform.

**A version older than the newest one published is refused** with `409`: it would
become the latest release and bring back its metadata. Publishing the same version
again, a newer one, or any `dev-` version goes through; a version `Gem::Version`
cannot read is not compared.

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
expected: the kinds a platform's updater registers · [ ] the CI builds it · [-] the CI does not, upload it by hand · [~] optional, may be absent

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
ci :woodpecker

# named explicitly (recommended — the host says what its CI is)
ci :woodpecker do
  url            ENV["WOODPECKER_URL"]
  api_token      ENV["WOODPECKER_API_TOKEN"]
  repo_owner     ENV["WOODPECKER_REPO_OWNER"]
  public_key_url "https://ci.example.org/api/signature/public-key"
  update_server  "https://catalog.example.org"
  tools          "registry.example/ci-tools:latest"   # every platform's, unless it names its own

  platform :godot,  builder: "registry.example/godot-builder:4.6"
  platform :phaser, builder: "registry.example/phaser-builder:latest",
                    web_shell: "https://example.org/phaser/index.html"
  platform :dos,    builder: "registry.example/dos-builder:latest", forge_release: true
end

# this host builds nothing: /api/ci/* answers 503, /build/config refuses,
# and the admin pipeline actions hide themselves
ci :none
```

A Woodpecker adapter takes `url`, `api_token`, `repo_owner`, `public_key` or
`public_key_url`, and `update_server`; `ci :gitlab` takes `url`, `api_token`,
`webhook_secret` and `update_server`. Settings left out come from ENV, as before.
A `platform` needs a `builder` and may name an `exporter`, `tools`, `web_shell`,
`bundle_id_prefix` and `forge_release`. Any object with the adapter's methods
works as well: `ci MyCI::Adapter.new`. The block builds
`WarpEngine::CI::Woodpecker::Adapter.new(url:, ..., platforms: { "godot" => { builder: ... } })`
into `config.ci_adapter`.

`GET /api/ci/pipelines` and `GET /api/ci/pipelines/:id/status` answer in camelCase
like every other endpoint (`repoOwner`, `repoName`, `repoId`, `lastPipelineStatus`,
`lastPipelineAt`, `softwareName`, `latestRun`), and each repository id appears under
one name only.

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
there — and an empty map (default) disables the feature. `tools` is an optional
image for the helper steps (version, lint, minify, docs, upload, publish): without
it they run in `alpine` and install what they need first on every run (`apk add`
git, jq, curl, zip, lua5.4; `luarocks install` luacheck and ldoc for tic80); with
it they run in that image and install nothing, so it must already have those, with
Lua 5.4 as `lua`. Set the Woodpecker side with
`WOODPECKER_CONFIG_EXTENSION_ENDPOINT=https://your-host/build/config` (or
per-repo in Settings → Extensions). Templates live with the adapter, in
`lib/warp_engine/ci/woodpecker/platforms/<platform>/pipeline.yaml.erb` — the
YAML dialect belongs to the provider, so a second adapter brings its own.

Keys of the marker besides `platform` and `name` are **options** the platform's
template may read (letters, digits, `_ . -` only; anything else is dropped). The
generated pipeline takes the marker file's place; the repo's **other** config
files (`.woodpecker/*.yaml`) are passed back unchanged, so a repo can keep a
workflow of its own — a server deploy, say — next to the generated one.

#### Steps every pipeline shares

The engine adds these steps to every template it renders, so no template carries them:

- **`version`**, first. The version comes from the source — `metadata.json`'s
  `version`, or the `-- version:` line of the Lua header on tic80 (a registered
  platform names its own with `version_source:`) — and on a tag from the tag too: a
  version tag (`v1.2.3` or `1.2.3`) has to match the source, and is the version where
  the source names none. Off the repo's default branch (`CI_REPO_DEFAULT_BRANCH`,
  `CI_DEFAULT_BRANCH`; `main` or `master` where the CI names none) it becomes
  `dev-<version>-<branch>`, and on a `dev-<branch>` tag likewise; with no version at
  all the build is `dev-<commit>`, which is never the latest. It writes `.version`,
  which every later step reads.
- **`tag`**, after a push (see below), unless the marker says `release: push`.
- **`release`**, last, only with `forge_release: true` in the platform's entry, and
  only on a version tag (a `dev-` tag makes none): the forge release of the tag, named `<title> <tag>`, with
  `RELEASE_NOTES.md` as its text. It attaches the files a build listed in
  `.release-assets`, or else the ones the upload step uploaded (`<name>-<version>.*`
  and `<name>-<version>-*`, without the metadata). On Woodpecker it is a Gitea or
  Forgejo release made with the `gitea_token` secret; on GitLab a GitLab release whose
  files are in the project's generic package registry, made with the job token.

Every template names its steps the same way: the one that sends the files to
`/build/upload` is `upload`, the one that calls `/build/publish` is `publish`.

#### When a pipeline publishes: tags

A generated pipeline builds on every event; the release steps (`package`, `upload`,
`publish`, `release`) run on tags only — Woodpecker `when: event: tag`, GitLab
`rules: if: $CI_COMMIT_TAG`. Nobody has to make the tags: the `tag` step, after
every push build, makes them from the version.

- **A new version** gets its tag: `metadata.json` says `1.2.0` and there is no
  `v1.2.0` yet, so the step tags the pushed commit `v1.2.0`, and that tag's pipeline
  releases it. Raising the version in the source is the whole release.
- **A version tagged already** releases nothing: a push that leaves the version as
  it is only builds.
- **A dev build** (`dev-<version>-<branch>` off the default branch, `dev-<commit>`
  with no version) moves the branch's `dev-<branch>` tag onto the pushed commit, so
  every push releases the branch's newest dev build. A dev tag makes no forge release.

Generated Woodpecker pipelines start on every event but `release` (a workflow
`when`, left out where a template has its own): moving a dev tag makes the forge
send a release event as well, which would build the same commit twice.

A tag made by hand works as before, and the step leaves it alone. The step needs a
token that may write tags: on Woodpecker the `gitea_token` secret (a Gitea or
Forgejo token with repository write access; a global or organization secret serves
every repo), on GitLab a `TAG_TOKEN` CI/CD variable (an access token with the `api`
scope), as the job token cannot write tags.

A marker with `release: push` goes back to the way before 1.9 for that repo: it
uploads and publishes on every push and makes no tags.

```yaml
platform: godot
release: push
```

A platform may say it releases from tags only (`release_rule "tag"` in its service);
then a marker cannot turn that off. `dos` is such a platform.

#### Values a template takes from the host

A platform's entry may carry values that differ from host to host; the templates
hold no host's addresses:

- `web_shell:` — the bevy, ebitengine and phaser browser builds wrap the game in an
  `index.html` page. With a URL here the pipeline downloads it; without one it
  takes the repo's own `web/index.html`.
- `bundle_id_prefix:` — the LÖVE macOS app's bundle id is `<prefix>.<name>`
  (default `org.warpengine`).

```ruby
platforms: {
  "bevy" => { builder: "registry.example/bevy-builder:1", web_shell: "https://example.org/bevy/index.html" },
  "love" => { builder: "registry.example/love-builder:1", bundle_id_prefix: "com.example" }
}
```

#### The `c64` and `plus4` platforms

The pipeline assembles `main.asm` with ACME into `<name>.prg`. A marker with
`build: make` hands that step to the repo's Makefile instead: it runs
`make <name>.prg` in the builder image, and the rest — packaging the players,
upload, publish — is the same. WARP64U, written in C with cc65, is built this way:

```yaml
platform: c64
build: make
```

The `exporter` image packages the players. Its contract is one command,
`commodore-pack <c64|plus4> <name> <version>`, run in the workspace next to
`<name>-<version>.prg` and `metadata.json`, which writes `<name>-<version>.html.zip`
and the `-linux-x64.zip`, `-win-x64.zip` and `-mac-arm64.zip` players (the
`build/c64-tools` `player.Dockerfile` is one such image). Only the PRG is required:
a program without the players still publishes, and only the players that were
built are uploaded.

#### The `dos` platform

DOS programs (with an optional Win32 build) are published like games, from a
tag. Like every other platform, the repo holds a `platform: dos` marker and a
`metadata.json`; the steps are commands of the builder image (`build/dos-tools`,
`git.teletypegames.org/build/dos-builder`): `dos-check`, `dos-build` and
`dos-test` on every event, `dos-pack` on a tag (it lists the release zips and
executables in `.release-assets` for the shared release step). The repo's side of the contract is `SOURCE/build.sh` (Open Watcom
in `$WATCOM`), its tests where the commands look for them (`SOURCE/test/unit/run.sh`,
`SOURCE/test/run.sh`, `runw32.sh`, `run.py`, `server/test`), and the `dos` block of
`metadata.json`, which says what a release holds:

```json
{ "name": "dosinst", "title": "DOSINST", "category": "tool",
  "dos": { "folder": "DOSINST",
           "files": ["DOSINST.EXE", "DOSINST.CFG", "README.md", "LICENSE"],
           "settings": ["DOSINST.CFG"],
           "store_name": "DOSInst Store", "store_description": "…",
           "win32_folder": "DOSINSTW",
           "win32_files": ["DOSINSTW.EXE", "DOSINST.CFG", "README.md", "LICENSE"],
           "win32_store_name": "…", "win32_store_description": "…" } }
```

`settings` go into the release zip but not into a store update, so an update never
overwrites an installed program's configuration. The uploaded metadata keeps the `dos`
block: a `folders` shelf (see *Shelves*) reads the folder, the settings and the store
text from it.

The version is the tag without its `v`. The folder zip becomes the `cartridge`
(`dosinst-0.6.0.zip`) and the Win32 one the `win_x86` asset
(`dosinst-0.6.0-win-x86.zip`), byte for byte the files of the forge release.
DOS releases are download only.

### Platforms of your own

The built-in platforms are the gem's; a host adds its own in the initializer — a
service class, the kinds its CI builds and a pipeline template per CI adapter:

```ruby
register_platform "amiga",
                  service:        "AmigaPlatform",
                  built_kinds:    %w[cartridge],
                  templates:      { woodpecker: Rails.root.join("ci/amiga.woodpecker.yaml.erb") },
                  version_source: "cat VERSION"
```

```ruby
class AmigaPlatform
  include WarpEngine::Platforms::Updatable
  include WarpEngine::Platforms::Builds::BuildCartridge

  platform "amiga"
  label "Amiga"
  required_kinds "cartridge"

  def cartridge_ext = ".adf"
end
```

From then on `amiga` is a platform like the others: a software may be on it, the
publish runs its service, the admin lists it, the config extension renders its
template (the same ERB variables as the built-in ones: `name`, `builder`, `exporter`,
`tools`, `options`, …) with the shared `version` and `release` steps around it
(`version_source:` is the shell command that prints its version; `metadata.json`'s by
default), and a shelf may serve it. A service may also say `release_rule "tag"`, and
answer `self.shelf_folder(metadata, kind)` for a `folders` shelf (see *Shelves*). The CI adapter still needs an entry
for it under `platforms:`, as every platform does. A host may also register a
built-in name to replace that platform's service or template.

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
storage :local   # default
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

storage MyObjectStore.new
```

`GET /api/download` and `GET /file/*` both go through the adapter, so a
signing adapter turns them into redirects without any further change.
`WarpEngine::DownloadService#create` still returns an absolute path (and
`nil` when there is none), so existing callers keep working;
`#locate` is the new entry point that can also hand back a redirect.

**Serving only.** Ingestion — `POST /build/upload`, archive extraction and
the admin file manager — still writes to the local disk. A remote adapter
needs its own upload path today.

## Outlets

An outlet is a format the catalog leaves the engine in. Three layers make up the way
out, and every outlet sits on the same two below it:

```
outlets      wecp (/api, always on)   shelf (folders, materialized)   assembly64 (/leet/search, served)
offer        WarpEngine::Catalog::Offer — which titles, which release, which file
models/seams Software, Release, ReleaseAsset · Storage, AccessPolicy, Images, DownloadService
```

- **`wecp`**, the WarpEngine Catalog Protocol: the JSON API under `/api` and the files
  under `/file`. Always on, never configured, and the only outlet that knows a caller:
  sign-in, entitlements and gated titles live here.
- **`shelf`**: a folder with an `INDEX.TXT` (below). *Materialized*: rewritten whenever
  the catalog changes.
- **`assembly64`**: the Assembly64 search API (below). *Served*: answers requests.

Every outlet but `wecp` offers what an anonymous caller may have without a gate: the
kept titles of its platforms with a listed status, each with the latest release that
has the asset (`WarpEngine::Catalog::Offer`). So a shelf and an Assembly64 server list
the same titles, and a change to that rule changes both.

```ruby
shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG"   # same as outlet ..., type: :shelf
outlet :assembly64, type: :assembly64, platforms: %w[c64], hosts: %w[a64.example.org],
                    repo: "acme", repo_name: "Acme Games"
```

`GET /api/service` lists every outlet under `outlets` (`key`, `type`, `platforms` and
what the type adds). The configuration is checked at boot like the shelves: an unknown
type, platform or kind, or two outlets with one key, stops the application.

```sh
bin/rails warp_engine:outlets:check   # every outlet and what it offers (STRICT=1 fails on anything left out)
bin/rails warp_engine:outlets:sync    # rewrite every materialized outlet (DRY_RUN=1 only says what would change)
```

**A type of your own** subclasses `WarpEngine::Outlets::Base`, names itself with
`type_name`, includes `WarpEngine::Outlets::Materialized` (and defines `sync!`) or
`WarpEngine::Outlets::Served` (and defines `self.draw_routes(mapper)`), and is
registered by name:

```ruby
register_outlet_type :feed, "Acme::FeedOutlet"
outlet :feed, type: :feed, platforms: %w[tic80]
```

A materialized outlet is synced after every change that can alter its offer (publish,
software, release, asset or status saved or soft-deleted), for the outlets carrying the
platform; one that fails is logged and does not fail the save.

## Assembly64

An `assembly64` outlet answers the Assembly64 search API under `/leet/search`, as
`hackerswithstyle.se` does, so the Assembly64 browser of an Ultimate (C64 Ultimate,
Ultimate 64, 1541 Ultimate) lists the catalog's titles and runs them from the menu.

```ruby
outlet :assembly64, type: :assembly64,
       platforms: %w[c64], kinds: %w[cartridge],
       hosts: %w[a64.example.org],
       repo: "acme", repo_name: "Acme Games",
       categories: { utility: "tools" }
```

| Option | |
|---|---|
| `platforms` | the platforms on offer (default `["c64"]`) |
| `kinds` | the asset kinds on offer (default `["cartridge"]`); the file's extension is its `type` |
| `statuses` | optional; without it, the statuses whose `default_visible` is set |
| `hosts` | the host names it answers (`host` for one); empty for any |
| `repo`, `repo_name` | the entry of the `repo` preset (default the outlet key, `WarpEngine`) |
| `categories` | catalog category → Assembly64 category; unnamed ones are tried as is, then with an `s`, then `default_category` |
| `default_category` | default `games` |
| `client_ids` | the `Client-Id` values accepted; empty (default) for any |
| `max_results` | the most results a search returns (default 100) |
| `name_length` | the longest file name, extension included (default 16) |

| Endpoint | Answers |
|---|---|
| `GET /leet/search/aql/presets` | the search form: `repo`, `category`, `type`, `date` (from what is on offer), `latest`, `sort`, `order` |
| `GET /leet/search/aql?query=` | a search, at most `max_results` results and under 16 000 bytes of JSON (the stock firmware drops a larger one) |
| `GET /leet/search/aql/START/COUNT?query=` | a page of a search |
| `GET /leet/search/entries/ID/CATEGORY` | `contentEntry`: the title's files (`path`, `id`, `size`, `date`) |
| `GET /leet/search/bin/ID/CATEGORY/FILE` | the file, `application/octet-stream`, through the download service (access check, download log) |

A result is `id` (the software id, a string), `name` (title), `group` (author), `year`,
`category` (the Assembly64 id of the category) `updated` and `type`. The query is
Assembly64's AQL, `(name:"ra") & (category:games) & (date:2026)`: `name`, `group`,
`repo`, `category`/`subcat`, `type`, `date`/`year` and `latest` narrow it, `sort`
(`name`, `group`, `year`) and `order` order it, and a condition on anything else
(`handle`, `event`, `rating`) matches nothing. A file is named as on a shelf: the
`shelf_name` or `name`, in capitals, plus the extension (`ARIADNE.PRG`).

**Reaching it.** The stock firmware asks `hackerswithstyle.se` (or Commodore's
CommoServe) and nothing else, over plain HTTP on port 80. A machine with a configurable
server list — the Spiffy patch's `/flash/config/server.json` — needs one entry:

```json
{ "assembly64": [ { "name": "Assembly64" }, { "name": "Acme Games", "host": "a64.example.org" } ] }
```

so serve the outlet's host over plain HTTP on port 80, without a redirect to HTTPS, and
mount the engine at `/` (the paths are fixed by the clients).

## Shelves

A shelf is a folder the engine keeps in step with the catalog: for one platform, the
latest build of every public title, under a fixed name with no version in it, and an
`INDEX.TXT` that lists them. It is for clients that cannot read the JSON API — a C64
store that fetches the index and the files over plain HTTP, a DOS installer that reads
folders over FTP — and it is off unless the host asks for one:

```ruby
shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16, preview: "c64",
            urls: [ "ftp://ftp.example.org/C64", "http://archive.example.org/C64" ]
shelf :dos, kind: %w[cartridge win_x86], layout: "folders", path: "shelves/APPS",
            urls: [ "ftp://ftp.example.org/APPS" ]
```

| Key | |
|---|---|
| `platform` | whose titles go on the shelf |
| `kind` | which asset of the release (`ReleaseAsset` kind), or a list of them |
| `layout` | `flat` (default): one file a title; `folders`: one folder a title (below) |
| `path` | the folder, relative to `file_container_path` |
| `extension` | `flat` only: the extension on the shelf, in capitals |
| `name_length` | the longest file name, extension included (default 16); for `folders`, the longest folder name (default 8, as DOS has it) |
| `statuses` | optional; without it, the statuses whose `default_visible` is set |
| `urls` | optional: where the host serves the folder (`ftp`, `http`, `https`) |
| `preview` | optional, `flat` only: a picture of each title beside its file (`c64`, below) |

The configuration is checked at boot: an unknown platform, kind or layout, a path outside
the container, two shelves in one folder, a URL without one of those schemes, or a storage
adapter other than `:local` stops the application rather than leaving a shelf empty.

**Serving it is the host's.** The engine writes the folder; it runs no FTP or HTTP server
of its own. A host points its servers at the folder and names their addresses in `urls`,
which `GET /api/service` lists under `shelves` — so a page or a client can say where a
shelf is. A machine that cannot speak HTTPS cannot ask the API, so a client for one keeps
its own default address and lets its user change it.

**What goes on a shelf.** Every kept software of the platform whose status is listed and
which the access policy shows an anonymous caller without a gate; of each, the latest
release (`Release.latest_non_dev`) that has the asset. The file is named after the
software's `shelf_name`, or, without one, its `name` — in capitals, with anything but
`A–Z`, `0–9` and `-` turned into a dash, cut to fit `name_length`. Two titles that would
share a name: the older one keeps it, the other is left off and reported.

```
shelves/C64/
  INDEX.TXT
  ARIADNE.PRG
  BLESSINGOFRA.PRG
```

**`INDEX.TXT`** is ASCII, one title a line, sorted by title, after a header naming the
format and the fields:

```
#SHELF 2 file|version|size|crc32|title|author|description|category|preview
ARIADNE.PRG|1.1.0|10561|3c0f5d2a|Thread of Ariadne|Teletype Games|Co-op labyrinth for two.||ARIADNE.PVW
WARP64U.PRG|1.0.0|31816|5e1d0c3b|WARP64U|Teletype Games|The store on the C64.|tool|WARP64U.PVW
```

`crc32` is zlib's, in hexadecimal. `category` is the software's category key (empty for
none), `preview` the name of its picture on the shelf (empty for none). Text is
transliterated to ASCII, `|` and line breaks become spaces, and a line is at most 255
bytes — the description is what gets cut. Version 1 of the format (1.2–1.9) ended after
the description; the two fields came after it so that a version 1 reader still reads a
version 2 line right.

**Previews.** A flat shelf with `preview: "c64"` also holds `NAME.PVW` beside `NAME.PRG`
for every title with an image in its gallery (the default one, else the first): a C64
bitmap a client can put on the screen as it comes (`WarpEngine::ShelfPreview::C64`),
9003 bytes in hires, 10003 in multicolor:

| Bytes | |
|---|---|
| 1 | mode: 0 hires, 1 multicolor |
| 1 | background color (multicolor) |
| 1 | border color |
| 1000 | screen matrix |
| 1000 | color RAM, multicolor only |
| 8000 | bitmap, 8 bytes a cell, cells row by row |

The image is read as a 384x272 VICE frame when its border band is of one color, as a
320x200 screen when its shape is near that, and is fitted into the screen otherwise. Every
pixel takes the nearest of the 16 colors, and the picture is drawn both ways — two colors
in each 8x8 cell, or a shared background and three colors in each 4x8 cell — and the one
closer to the image is kept. A preview is rendered again when it is missing, its title
gets a new release, or its image file is newer; an image that cannot be read leaves the
title without one (and is logged).

**A `folders` shelf** holds a folder for each title and kind, the layout DOSINST reads:
the asset is a zip with the folder at its top, and the platform's service names the folder
from the release's uploaded metadata (`shelf_folder(metadata, kind)`; on `dos` the `dos`
block: `folder` for the `cartridge`, `win32_folder` for `win_x86`). The engine unpacks the
folder without its `settings` files, so an update never overwrites an installed program's
configuration, and writes two files into it:

```
shelves/APPS/
  INDEX.TXT
  DOSINST/  DOSINST.EXE  README.md  LICENSE  INFO.INI  FILES.LST
  DOSINSTW/ DOSINSTW.EXE README.md  LICENSE  INFO.INI  FILES.LST
```

- `INFO.INI`: `[program]` with `name`, `description`, `version` and `platform` (`DOS` or
  `WIN32`), CRLF line ends;
- `FILES.LST`: `crc32 size path` for every file but itself, sorted, CRLF line ends, which
  the client checks its downloads against.

A title without the metadata, or with a folder name that does not fit, is left off and
reported. `INDEX.TXT` lists the folders as a flat shelf lists files (its name has a dot,
so DOSINST does not take it for a program). A folder is built next to the old one and
swapped in. Only folders the index listed are ever removed, so a folder put there by hand
stays.

**When it changes.** A shelf is rebuilt whole, from the database, whenever something
that decides its content changes: a publish (`warp_engine.publish`), and any committed
change or soft delete of a software, a release, a release asset or a status. A rebuild
that changes nothing writes nothing; a file is copied again only when its version, size
or source is newer. The new files land under a temporary name and are renamed into
place, `INDEX.TXT` is replaced last, and only then are the files that left the shelf
removed — so a reader never finds a line whose file is missing. A rebuild that fails is
logged and does not fail the save that caused it. A flat shelf's folder belongs to the engine;
nothing else should write into it.

A change the engine cannot see — an access policy that starts gating a title for
reasons of its own — needs a rebuild by hand:

```sh
bin/rails warp_engine:shelves:check            # what each shelf holds and leaves out (STRICT=1 fails on the latter)
bin/rails warp_engine:shelves:sync             # rebuild every shelf
DRY_RUN=1 bin/rails warp_engine:shelves:sync   # only say what would change
```

## Images

An image is not a catalog concept: the same picture library serves covers,
screenshots, avatars and whatever else a site has. So the engine owns only the
link — `SoftwareImage`, ordered, with one default — while the `Image` model, the
uploaded files and the admin page live in the host. `rails g warp_engine:install`
writes a working one (`app/models/image.rb`, `app/controllers/api/images_controller.rb`,
a `create_images` migration); the engine talks to it through an adapter:

```ruby
image_class "Image"   # default
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

image_adapter MyImageLibrary.new
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
access_policy :open   # default
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

access_policy MyStore::AccessPolicy.new
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
access_token_owner_class  "User"      # nil (default): no sign-in at all
identity_verification_url "/devices"  # your page where a person types the code
device_code_ttl           600
device_code_interval      5
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
subject_resolver { |request| request.env["warden"]&.user }
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
| `GET /api/service` | What this deployment is: version, whether the catalog gates, how to sign in (or that you cannot), and its shelves with their addresses |
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

## Admin API

What the ActiveAdmin resources do — the catalog with its releases, assets, links
and images, the status and category vocabulary, platform links, download
statistics, pipelines, the artifact store and the application tokens — is also a
JSON API. It is **off by default**; a host turns it on in the initializer:

```ruby
WarpEngine.configure do
  admin_api do
    enable

    token_owner      "AdminUser"           # default: the application_tokens owner
    resources        :all                  # or :softwares, :releases, :downloads
    # read_only                            # GET only, the rest answers 405 (default: off)
    page_size        50
    max_page_size    200
    # rate_limit     300, per: 1.minute    # per token, Rails.cache (default: none)
    # public_openapi                       # the document needs no token (default: it does)
    # docs_ui                              # a Redoc page at /api/admin/v1/docs (default: off)
    # mcp                                  # MCP at /api/admin/v1/mcp (default: off)
    exclude_from_mcp :application_tokens, :device_grants
    authenticator    :application_token    # or ->(request) { WarpEngine::AdminApi::Principal.new(...) }
  end
end
```

- **Authentication**: `Authorization: Bearer <application token>` carrying admin
  scopes — `admin:read` (every GET), `admin:write` (every write), `admin:tokens`
  (the token and device-sign-in resources, reading included). Only a token whose
  owner is the admin owner class may hold them. A token can grant no admin scope
  it lacks, no `unrestricted`, and no expiry past its own.
- **Shape**: camelCase JSON; a list is `{ data: [...], meta: { page, perPage,
  total, totalPages, nextPage } }`, one record `{ data: {...} }`; errors are
  `{ error, details? }` with 400/401/403/404/405/409/422/429/502/503. Deleting does
  what the admin does (the record is destroyed; a token is revoked). The last
  write wins, as in the admin; there are no batch operations.
- **Discovery**: `/api/service` carries an `admin` key (null while off) with the
  addresses; `GET /api/admin/v1/me` tells a token what it may use.
- **OpenAPI**: `GET /api/admin/v1/openapi.json` (or `.yaml`) is generated from
  the same registry that routes the requests, so it describes exactly what this
  host serves: disabled resources, write operations under `read_only` and parts
  without CI or client sign-in are left out. Each operation carries
  `x-required-scope`.
- **MCP**: with `mcp` in the `admin_api` block and `gem "mcp"` in the host's Gemfile
  (the engine refuses to boot without it), `POST /api/admin/v1/mcp` is a stateless
  Streamable HTTP MCP server. Every operation is a tool of the same name as its
  `operationId`, with the same JSON Schema for input and the same answer as
  structured content; `tools/list` shows only what the token may call. Uploads and
  the `mcp_exclude` resources stay out — a new plain token has no business in a
  model's context.
- **Audit**: every successful write instruments `warp_engine.admin_api.write`
  with the principal, the operation and `via: :http` or `:mcp`.

```sh
claude mcp add --transport http warp-admin https://example.org/api/admin/v1/mcp \
  --header "Authorization: Bearer $TOKEN"
```

## Upgrading to 1.11

- **Shelves are outlets.** Nothing to change: `shelf` and `WarpEngine::Shelves` work as
  before, and the shelf files are the same byte for byte. `GET /api/service` adds
  `outlets` beside `shelves`.
- **`ShelfRefreshing` is `OutletRefreshing`**, and the private hook it calls is
  `outlet_platform` (was `shelf_platform`). Only a host that included the concern in a
  model of its own needs to follow.

## Upgrading to 1.9

- **Releases come from tags, and the pipeline makes them.** A push no longer
  publishes; it builds and tags (see *When a pipeline publishes: tags*). Every
  Woodpecker repo needs the `gitea_token` secret, every GitLab project a `TAG_TOKEN`
  variable, before its next pipeline — a missing secret stops the pipeline. A repo
  that should publish on every push says `release: push` in its marker.
- **The default branch is the repo's**, not `main` or `master`: a repo whose default
  branch is `develop` publishes its version from `develop`.
- **`/build/publish` refuses an older version** than the newest published, with `409`.
- **A platform service's `release_rule` is `nil`** unless it sets one (it was `"push"`).

## Upgrading to 1.7

- **The shared `version` step.** Templates no longer carry a version step; the engine
  adds one (see *Steps every pipeline shares*). A version tag that does not match the
  version in the source now fails the pipeline, and a build with no version is
  `dev-<commit>` (it was the bare commit hash, published as a release).
- **`forge_release` works on every platform**, as the shared `release` step. `dos-release`
  is gone from the dos builder; `dos-pack` writes `.release-assets` instead.
- **No `store:` step.** The dos pipeline no longer sends folders anywhere over SSH: a
  `folders` shelf builds the store from the catalog. Drop `store:` from the `dos` entry
  and `store_secret` from markers, and add the shelf. The uploaded metadata keeps its
  `dos` block (it was stripped), so a release published before 1.7 needs its
  `<name>-<version>.metadata.json` given the block back, or a new release, before it can
  go on a folders shelf.
- **Step names.** `artifact` is `upload` on c64, plus4, ebitengine and dos; `package` is a
  release step under `release: tag`.
- **`shelves`' `kind` may be a list**, and a `Shelf` has `kinds` (not `kind`), `layout`
  and `urls`.
- **LÖVE pipelines no longer upload `<name>-<version>.love.zip`**, which no asset kind took.

## Upgrading to 1.5

- **The templates hold no host's addresses.** The bevy, ebitengine and phaser browser
  builds took their `index.html` from Teletype Games' forge; now they take the
  platform entry's `web_shell:` URL, or the repo's own `web/index.html` without one.
  The LÖVE macOS bundle id is `<bundle_id_prefix>.<name>`, `org.warpengine` by default
  (it was `org.teletypegames`). Set both in the CI adapter's `platforms:` to keep a
  pipeline as it was.
- **A publish without the platform's required kind answers `422`** instead of recording
  a release without it (the `cartridge` on tic80, c64, plus4 and dos; `html` elsewhere).
- **A c64 or plus4 release without a browser player publishes**; before, it failed.
- `WarpEngine::Platform::NAMES` is the built-in list; `Platform.names` adds the ones a
  host registers, and is what to call.

## Behavioral notes

- Every model is soft-deleted: a `deleted_at` column and the `kept` / `discarded` scopes
  of `WarpEngine::SoftDeletable`. Since 0.10 there is no `default_scope`, so a query does
  not filter by itself: a host asks for `WarpEngine::Software.kept`, and a host upgrading
  from 0.9 or earlier adds `.kept` where it relied on the default scope.
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
