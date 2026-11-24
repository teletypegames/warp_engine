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
  named, and each platform is declared once (`lib/warp_engine/platform/builtin.rb`):
  the asset kinds it accepts and requires, which of them its pipeline builds, where
  its metadata comes from and its CI template. `Platform.names` lists them,
  `Platform.find!("godot")` answers with a value object that knows its `label`,
  `expected_kinds`, `built_kinds` and publishes an upload (`#publish`). Reference it
  instead of writing a platform list of your own — `PlatformLink::SUPPORTED_PLATFORMS`
  is kept as an alias of `Platform::NAMES`.
- **Runtimes (3.1)**: a release can play on the web in a runtime the engine keeps
  once, instead of a self-contained `html` build per release — EmulatorJS for the
  C64 and the Plus/4, the TIC-80 player, a host's own. A platform binds to one or
  more runtimes, a runtime serves many platforms, the page is rendered at
  `/play/<name>/<version>`. See *Runtimes*.
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
- **Outlets (1.11, one shape since 2.0)**: the formats the catalog leaves the engine
  in, side by side — the JSON API, shelves and an Assembly64 server — each built the
  same way, the last two over one shared decision of what is on offer
  (`WarpEngine::Catalog::Offer`), with room for types of the host's own. See *Outlets*.
- **Shelves (optional, 1.2)**: a platform's latest public builds as a flat,
  versionless folder with a plain-text `INDEX.TXT`, kept up to date by the engine
  itself — for clients too small to speak JSON over HTTPS (a C64 reading it over
  FTP). Off unless configured.
- **Assembly64 (optional, 1.11)**: the catalog as an Assembly64 search server, so a
  C64 Ultimate finds and runs its titles from the menu. Off unless configured.
- **Sync (optional, 4.5; 5.0)**: releases copied between engines — outbound to the
  peers this engine pushes to, inbound from the peers it accepts — each direction with
  its own filters (software, category, platform, status, channel, asset kind), a
  per-software switch, protection of what the CI published here, an event log linked to
  each software, and transports behind one interface (`http`: another engine's `/build`
  endpoints, a host may add its own). Off unless configured. See *Sync*.
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

- Rails >= 8.1
- A relational database (developed and tested against MySQL 8)
- Optional: ActiveAdmin + Devise in the host app for the admin UI

## Example stack (docker compose)

A whole studio on one machine — the catalog app, a Gitea forge and Woodpecker CI,
wired together by one `bin/setup` — lives in its own repository:
[engines/warp-engine-example](https://git.teletypegames.org/engines/warp-engine-example)
(until 5.1.0 it was `examples/compose` here). It takes this gem from the registry,
and `compose.engine.yml` there runs it against a checkout of this repository.
The sections below use that stack's addresses (`http://localhost:8080`,
`docker compose exec app …`).

### Stores for your catalog

The engine serves the Batocera and RetroArch store engines for *this* catalog
(see *Store engines*): once the catalog has a `we-batocera` (or `we-retroarch`)
release, a box installs with one line:

```sh
curl -fsSL http://192.168.1.20:8080/api/stores/batocera/install.sh | sh
```

The box has to reach the catalog at the address it sees (your machine's LAN
address for the example). The store's name, id, statuses and logo are the
defaults worked out from the catalog until you set them on the *Store Engines*
admin page or through the Admin API (`store_clients`).

The C64, Plus/4 and DOS clients read files, not the API: the example writes the
`c64`, `plus4` and `dos` shelves (see *Shelves*) and serves them with two small
containers, `shelf-http` (plain HTTP, the way a C64 with a network cartridge can
fetch them) and `shelf-ftp` (anonymous, read-only, passive FTP for WEDOS). For a
real machine on your network set `SHELF_HTTP_URL`, `SHELF_FTP_URL` and
`SHELF_FTP_ADDRESS` in `.env` to your machine's address; the clients themselves are
pointed there with their own config file (`WE64.CFG`, `WEDOS.CFG`).

### Publish a release by hand

The updater contract is nothing but a handful of HTTP calls, so you can play
the role of the CI pipeline yourself. The seed stores `UPDATE_SECRET` as an
application token for this:

```sh
# 1. Fake a build: metadata, a web build and a windows artifact, named by
#    convention (the love platform requires the .html.zip web build)
cat > demo-0.1.0.metadata.json <<'JSON'
{ "name": "demo", "title": "Demo Game", "author": "You", "desc": "Hello", "license": "MIT", "category": "demo" }
JSON
echo '<h1>demo</h1>' > index.html && zip demo-0.1.0.html.zip index.html
echo hello > game.bin && zip demo-0.1.0-win-x64.zip game.bin

# 2. Upload them (one request per file)
for f in demo-0.1.0*; do
  curl -fs -H "X-Update-Secret: example-update-secret" \
    -F "file=@$f" "http://localhost:8080/build/upload?name=demo&version=0.1.0"
done

# 3. Publish the release
curl -X POST -H "X-Update-Secret: example-update-secret" \
  "http://localhost:8080/build/publish?platform=love&name=demo&version=0.1.0"
```

`GET /api/software` now lists *Demo Game* with `html` and `win_x64` assets,
`http://localhost:8080/file/demo/0.1.0/html/index.html` serves the extracted web
build, and `GET /api/download?path=demo/0.1.0/demo-0.1.0-win-x64.zip` serves the
artifact while logging a download record.

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
bundle install
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

    # Which stores a graphical client offers on its first run (see "Store registry").
    # By default this catalog alone, named by the host name of its address.
    # store_name "My Studio"
    # store_registry [ :own, { name: "Friends' Games", catalog_url: "https://friends.example" } ]

    # Flat, versionless copies of a platform's latest builds (see "Shelves"),
    # and the other outlets (see "Outlets"). None by default.
    # shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16
    # outlet :assembly64, type: :assembly64, platforms: %w[c64], hosts: %w[a64.example.org]
  end
end
```

An unknown setting stops the boot with a `NoMethodError`, an unknown CI or platform
key with an `ArgumentError`, an outlet (a shelf among them) that does not check out with
a `WarpEngine::ConfigurationError`. `to_prepare` runs the block again on every code
reload; an outlet (by key), an additional resource (by subject and association) and a
platform (by name) replace their earlier selves instead of adding up.

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

1. **Upload** build artifacts into the release's folder of `file_container_path`
   (`<name>/<version>/`, see [File layout](#file-layout)), named by convention:
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

The same numbers are available as objects: `WarpEngine::AssetCoverageService.new(...)`
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
git, jq, curl, zip, lua5.4; `luarocks install` luacheck and ldoc for tic80;
doxygen for the c64 and plus4 docs); with
it they run in that image and install nothing, so it must already have those, with
Lua 5.4 as `lua`. Set the Woodpecker side with
`WOODPECKER_CONFIG_EXTENSION_ENDPOINT=https://your-host/build/config` (or
per-repo in Settings → Extensions).

Since 1.12 a platform has **one template for every CI**, in
`lib/warp_engine/ci/platforms/<template>.yaml.erb` (`commodore` serves both `c64` and
`plus4`). It holds only the platform's own steps, in a CI-neutral form, and the
adapter's renderer (`CI::Woodpecker::Renderer`, `CI::Gitlab::Renderer`) writes them —
and the shared steps around them — in its YAML dialect:

```yaml
check: false                         # optional: the template runs its own checks, no make check
steps:
  - name: build
    image: <%= builder %>            # the builder and exporter images are pulled on every run
    artifacts: [ "*.prg" ]           # what a GitLab job hands to the later stages
    environment: { KEY: value }
    commands:
      - make <%= name %>.prg
  - name: package
    release: true                    # only a release build runs it (on tags, when releases follow tags)
    image: <%= builder %>
    commands:
      - make dist
upload:                              # optional
  packages: [ jq ]                   # what the upload needs from apk without a tools image
  prepare: |                         # shell lines run before the upload
    cp dist/game.zip <%= name %>-$VERSION.zip
```

**Native targets** go through one shell function every template shares,
`warp_target` (`lib/warp_engine/ci/scripts/pack.sh`, prepended to a step that calls
it). The template gets `targets`, a Hash of every native kind the pipeline builds
(`kind` with `built`, a `win_`, `linux_` or `mac_` kind, `cli_` ones too) to its
arguments, so the list of targets lives only in the platform's kinds:

```erb
<%- targets.each do |kind, args| -%>
warp_target <%= args %> go_build <%= GO.fetch(kind).join(" ") %>
<%- end -%>
```

`warp_target SUFFIX MODE FUNCTION ARGS…` makes the folder `<name>-<version>-<target>`
(`$PKG_DIR`), runs the function in it with errexit, adds the repo's `LICENSE` and
`README`, zips it with that one root folder (`zip`, or `python3 -m zipfile` where the
image has none) and removes the folder. When the function fails, a target whose kind is
`optional` is left out with a warning; a `required` or an `expected` one (built, but
neither required nor optional) fails the step. A template must not use `${…}`:
Woodpecker substitutes it before the shell runs.

Keys of the marker besides `platform` and `name` are **options** the platform's
template may read (letters, digits, `_ . -` only; anything else is dropped). A
platform declares the ones it reads with `option` (`option :media, values: %w[prg d64],
description: "…"`); a value outside them does not reach the template, and the
platform description lists them for the developer tools. `release` (every platform
that does not force it) and `app` (a platform with variants) are listed there too. The
generated pipeline takes the marker file's place; the repo's **other** config
files (`.woodpecker/*.yaml`) are passed back unchanged, so a repo can keep a
workflow of its own — a server deploy, say — next to the generated one.

#### Steps every pipeline shares

The engine adds these steps to every template it renders, so no template carries them.
Their shell scripts are plain `sh` files, linted by shellcheck: `lib/warp_engine/ci/scripts/`
(`version`, `upload`, `publish`, `tag`, `release_files`) and each adapter's `scripts/`
(`forge.sh` — the forge's tag API — and `release.sh`).

- **`version`**, first. The version comes from the source — `metadata.json`'s
  `version`, or the `-- version:` line of the Lua header on tic80 (a registered
  platform names its own with `version_source:`) — and on a tag from the tag too: a
  version tag (`v1.2.3` or `1.2.3`) has to match the source, and is the version where
  the source names none. Off the repo's default branch (`CI_REPO_DEFAULT_BRANCH`,
  `CI_DEFAULT_BRANCH`; `main` or `master` where the CI names none) it becomes
  `dev-<version>-<branch>`, and on a `dev-<branch>` tag likewise; with no version at
  all the build is `dev-<commit>`, which is never the latest. It writes `.version`,
  which every later step reads.
- **`check`**, second, in the builder image: `make check` when the repo's Makefile has
  a `check` target, nothing otherwise. A template with `check: false` runs its own
  checks instead (electron: the app's `npm run check`).
- **`upload`** and **`publish`**, after the platform's steps, generated from the
  platform's kinds: the upload sends `<name>-<version>` plus the suffix of every kind
  the pipeline always builds (a required kind, or one declared `always: true`) and of
  `metadata.json` — failing when one is missing — and every other kind the platform
  accepts when the build made it; `publish` then calls `/build/publish`.
- **`tag`**, after a push (see below), unless the marker says `release: push`.
- **`release`**, last, only with `forge_release: true` in the platform's entry, and
  only on a version tag (a `dev-` tag makes none): the forge release of the tag, named `<title> <tag>`, with
  `RELEASE_NOTES.md` as its text. It attaches the files a build listed in
  `.release-assets`, or else the ones the upload step uploaded (`<name>-<version>.*`
  and `<name>-<version>-*`, without the metadata). On Woodpecker it is a Gitea or
  Forgejo release made with the `gitea_token` secret; on GitLab a GitLab release whose
  files are in the project's generic package registry, made with the job token.

The `upload`, `publish` and `release` steps, and a template step with `release: true`
(the `dos` and store-engine `package`), run on tags only when releases follow tags.
Every other template step, native packaging included, runs on every build, so a push
finds a broken target before the tag does.

#### When a pipeline publishes: tags

A generated pipeline builds on every event; the release steps (`upload`, `publish`,
`release` and a template's `release: true` steps) run on tags only — Woodpecker `when: event: tag`, GitLab
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
  `index.html` page. With a URL here the pipeline downloads it (and fails when it
  cannot); without one it takes the repo's own `web/index.html`, and bevy and
  ebitengine generate a minimal page where the repo has none.
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
upload, publish — is the same. WE64, written in C with cc65, is built this way:

```yaml
platform: c64
build: make
```

The `exporter` image packages the players. Its contract is one command,
`commodore-pack <c64|plus4> <name> <version>`, run in the workspace next to
`<name>-<version>.prg` and `metadata.json`, which writes the `-linux-x64.zip`,
`-win-x64.zip` and `-mac-arm64.zip` players (the `build/c64-tools`
`player.Dockerfile` is one such image). Only the PRG is required: a program without
the players still publishes, and only the players that were built are uploaded. On
the web a C64 or Plus/4 release plays in the EmulatorJS runtime (see *Runtimes*),
so the platforms take no `html` build.

A program too big for one PRG ships on a disk: with `media: d64` the build step runs
`make <name>.d64` (the Makefile writes the image, with `c1541` or `oscar64 -d64=`),
and the `.d64` is the release's `cartridge` in place of the PRG. Everything else is
the same: `commodore-pack` puts the disk next to the players, and EmulatorJS
autostarts it. A flat shelf of `.PRG` files leaves such a title out.

```yaml
platform: c64
build: make
media: d64
```

A repo with C sources under `src/` (Oscar64, cc65) also gets the docs of every
release: the `docs` step runs Doxygen over `src/` with `README.md` as the main
page and the source browser on, and uploads `<name>-<version>-docs.zip`, which
the catalog opens like the docs of a TIC-80 cart. The comments may stay plain
`/* */` ones: a filter reads the first comment of a file as its description and
a comment above a declaration as its documentation. A `Doxyfile` in the repo is
read first, so it can add to the settings. An assembly-only repo builds no docs;
the kind is optional, so nothing is missing.

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
{ "name": "we-dos", "title": "WEDOS", "category": "tool",
  "dos": { "folder": "WEDOS",
           "files": ["WEDOS.EXE", "WEDOS.CFG", "README.md", "LICENSE"],
           "settings": ["WEDOS.CFG"],
           "store_name": "WEDOS Store", "store_description": "…",
           "win32_folder": "WEDOSW",
           "win32_files": ["WEDOSW.EXE", "WEDOS.CFG", "README.md", "LICENSE"],
           "win32_store_name": "…", "win32_store_description": "…" } }
```

`settings` go into the release zip but not into a store update, so an update never
overwrites an installed program's configuration. The uploaded metadata keeps the `dos`
block: a `folders` shelf (see *Shelves*) reads the folder, the settings and the store
text from it.

The version is the tag without its `v`. The folder zip becomes the `cartridge`
(`we-dos-0.6.0.zip`) and the Win32 one the `win_x86` asset
(`we-dos-0.6.0-win-x86.zip`), byte for byte the files of the forge release.
DOS releases are download only.

#### The `electron` platform

Desktop apps written with [Electron](https://www.electronjs.org): a store client, a
launcher, a tool, or an HTML game that wants a window of its own. The repo is an ordinary
Electron project with `electron-builder` in its `devDependencies`, plus the
`platform: electron` marker and a `metadata.json`. The version comes from `package.json`.

The builder image (`git.teletypegames.org/build/electron-builder`, `electronuserland/builder:22-wine`
unchanged) runs one `binaries` step: `npm ci`, then the app's own `check` script (tests
that need no display, in place of `make check`) and `build` script when it has them, then

- `electron-builder --linux AppImage --x64`: the AppImage is the required `linux_x64`
  (`<name>-<version>-linux-x64.zip`);
- `electron-builder --win nsis --x64` through Wine: the installer is the optional
  `win_x64`.

A semver build version is written into the app (`extraMetadata.version`); a development
build keeps `package.json`'s. macOS (`mac_x64`, `mac_arm64`) is expected but not built:
Apple's signing needs a Mac, so a macOS package is built there and uploaded with
`/build/upload` like any other asset. Electron releases are download only, with no web
build to play.

The Windows installer needs an x86_64 CI agent: Wine does not start in an emulated amd64
container on an Apple Silicon machine (16 KB memory pages). There the optional `win_x64`
is left out with a warning, so the rest of the release still goes out.

#### The `golang` platform

Programs written in [Go](https://go.dev), in two variants the marker picks with `app:`
(stored on the software as its `app`):

```yaml
platform: golang
app: cli          # the default; or app: gui
```

- `cli`: a command-line program. The pipeline cross-compiles the main package at the
  repository root with `CGO_ENABLED=0` for `cli_linux_x64` (required), `cli_win_x64`,
  `cli_linux_arm64`, `cli_mac_x64` and `cli_mac_arm64` (`<name>-<version>-linux-x64-cli.zip`
  and so on); a target that does not compile is left out with a warning. These kinds are
  *download only* (`launch: false` on their assets in the catalog): a client installs
  them but never starts them.
- `gui`: a desktop program (e.g. [Gio](https://gioui.org)). `linux_x64` (required, cgo),
  `win_x64` (without cgo, `-H=windowsgui`) and `linux_arm64` (cgo with the aarch64 cross
  gcc) are built as the usual launchable native kinds; `html` is built from a
  `GOOS=js GOARCH=wasm` build when the program compiles to it (with `web/index.html`, or
  a generated page); `mac_x64` and `mac_arm64` are uploaded by hand.

Each zip holds one root folder (`<name>-<version>-<target>`, `-cli` at the end for the
cli kinds) with the binary, `README.md` and `LICENSE`. The version is `metadata.json`'s.

### Platforms of your own

The built-in platforms are the gem's; a host adds its own in the initializer, with the
same DSL the built-in ones are declared with (`WarpEngine::Platform::Builder`):

```ruby
register_platform "amiga" do
  label "Amiga"
  kind :cartridge, ext: ".adf", required: true   # a publish fails without it
  kind :html                                      # built when the pipeline can
  kind :mac_arm64, built: false                   # accepted, uploaded by hand
  metadata :json                                  # or :lua, or a callable taking the upload
  release_rule :tag                               # optional: releases follow tags only
  version_source "cat VERSION"                    # default: metadata.json's version
  ci template: Rails.root.join("ci/amiga.yaml.erb"), machine: "a500"
end
```

The kinds are the `WarpEngine::AssetKinds` (`cartridge`, `source`, `html`, `docs`,
`win_x64`, …): each knows its upload name (`<name>-<version>-win-x64.zip`) and whether
the engine unpacks it (`html`, `docs`), so a platform only says which ones it has.
A platform whose software comes in kinds of program declares a `variant` for each,
with the kinds of its own next to the shared ones; the software's `app` (the
`app:` marker option, sent with the publish) picks one, and the first variant, or the
one marked `default: true`, is the default:

```ruby
register_platform "amiga" do
  kind :docs                                     # every variant
  variant(:game, default: true) { kind :cartridge, ext: ".adf", required: true }
  variant(:tool) { kind :cli_linux_x64, required: true }
end
```

`WarpEngine::Platform.for(software)` is the platform of a software for its variant.
A kind without a suffix of its own may take a list of extensions, the preferred first
(`kind :cartridge, ext: %w[.prg .d64]`): a release then carries one of them, the first
the upload has.
`ci template:` is a CI-neutral template (see *Pipeline configs*; the keyword arguments
after it are extra template variables), and `shelf_folder` takes a callable
`(metadata, kind)` for a `folders` shelf (see *Shelves*).

From then on `amiga` is a platform like the others: a software may be on it, a publish
runs the engine's publish steps (`WarpEngine::Publish`: collect the assets, read the
metadata, record the catalog), the admin lists it, every CI adapter renders its
template with the shared steps around it, and a shelf may serve it. The CI adapter
still needs an entry for it under `platforms:`, as every platform does. A host may
also register a built-in name to replace that platform.

The pre-1.12 form — `register_platform "amiga", service: "AmigaPlatform",
built_kinds: [...], templates: { woodpecker: ... }` with a service class including
`WarpEngine::Platforms::Updatable` and the `Builds::Build*` modules — still works and
is deprecated: the service's declarations become a definition, its `update` publishes
through `WarpEngine::Publish`, and its adapter-specific template is still rendered
with the shared steps around it.

### Platform descriptions for developer tools

An editor extension or a scaffolder learns the platforms from the engine instead of
knowing them itself. Three public endpoints describe them:

| Endpoint | Answer |
|---|---|
| `GET /build/platforms` | `{ "platforms": [ ... ] }`, one description per platform |
| `GET /build/platforms/:name` | one description, 404 for an unknown platform |
| `GET /build/platforms/:name/metadata-schema` | the JSON Schema (2020-12) of the platform's metadata |

A description holds the platform's `kinds` (with the upload name, every name it may have
in `uploads`, `required`, `optional`,
`built`, `always`), its `metadata` (`format` `json`, `lua` or `custom`, the `file` a developer
edits and the keys a publish reads), where the `version` comes from, the forced
`releaseRule`, the enabled `web` bindings with their runtime parameters, the `ci` side
(adapter, the marker file and its content, the builder image, whether the adapter builds
it), the marker `options` (`name`, `values`, `description`) and the host's `tooling`.

The schema has every key `MetadataReader` reads (a `license` is an SPDX id or
expression: `MIT`, not `MIT License`), `version` where the pipeline reads it
from `metadata.json`, the known categories as examples, the shelf-name rules and the `web`
section with the platform's binding keys and parameters.

`tooling` is free-form, what the host wants its developers' tools to know — where the
project template is, a demo, documentation:

```ruby
WarpEngine.configure do
  platform_tooling :c64, template: "https://git.example/build/c64-tools",
                         demo: "https://git.example/demos/c64-demo"
end
```

### Checking a publish before the push

`POST /build/check` (a JSON body: `platform`, `metadata`, optional `version` and
`kinds`) answers what the CI's publish would refuse, writing nothing:

```json
{ "ok": false, "problems": [ { "field": "shelf_name", "message": "RABBIT is taken on the C64 shelf", "level": "error" } ] }
```

It checks the required keys, keys a publish does not read, the shelf name, a stale
version, software ownership (with a bearer token), the `web` section and the kinds
the build would upload. An `error` would fail the publish, a `warning` would pass.

### Which commit a release came from

The publish step sends `CI_COMMIT_SHA` as `commit`; the release keeps it as
`commitSha` (Admin API, filterable on `GET /softwares/:id/releases?commitSha=`), and a
pipeline run reports its `commit`, `event` and `ref`, so a tool can tie the HEAD of a
working copy to its run and its release.

### Starting a software in one step (scaffold)

`POST /api/admin/v1/softwares/scaffold` (scope `admin:write`; body `name`, `title`,
`platform`, optional `app` (the variant of a platform that has them), `category`,
`description`, `license` and `forkOf`) does what starting a game takes:

1. an empty repository on the forge, in the configured organisation;
2. CI for it (`activate_forge_repo`) and its `Pipeline`, linked to the software;
3. a draft `Software` (status `development`) owned by the caller, with a *Repository* link;
4. an application token with `update` + `upload`, written into the pipeline's
   `application_token` secret;
5. the `warp_engine.scaffold` notification (`software`, `repo`, `pipeline`), where a host
   hangs its own integrations (an issue tracker project, a wiki page, an asset collection).

It answers the software, the repository URLs, the pipeline id and `warnings` for the steps
that did not go through (no CI, a refused secret). The project files are the tool's
business: it pushes them into the new repository, and the first push builds.

The forge is a seam like the others; without one, scaffolding answers 409:

```ruby
WarpEngine.configure do
  forge :gitea, url: "https://git.example", token: ENV["GITEA_API_TOKEN"], owner: "games"
end
```

The Gitea adapter (Forgejo answers the same API) needs a token that may create
repositories in `owner`.

### Playing a local build

`GET /play-preview/:platform(/:binding)?payload=message` renders the platform's runtime page
for a build that is not in the catalog yet, with the runtime version new releases get;
`params` (JSON, a metadata's `web.params`), `title` and `start` are optional. The page fetches
no build: it posts `{ type: "warpengine.ready" }` to its parent and plays the file posted back
to it — by its parent, or by a script of the page itself posting to its own window — as
`{ type: "warpengine.payload", name, data }` (`data` an `ArrayBuffer` or typed array).

A developer's tool serves the page itself, with the build: the WarpEngine Toolbox fetches it,
serves the runtime files from a local proxy and runs it in its panel or a local browser tab.
A public page could not fetch the build from the developer's machine (browsers block it).

### Release channels

A release is on a channel its version names (`WarpEngine::Channels`), never set by hand:

| Channel | Version | Who gets it |
|---|---|---|
| `stable` | `1.2.0` | everyone: the catalog's latest release, the outlets (shelves, Assembly64) |
| `beta` | `1.3.0-beta.1`, `1.0-alpha`, `2.0.0-rc.2` | listed; the latest only for a caller asking `GET /api/software?channel=beta` |
| `dev` | `dev-1.3.0-feature-x`, `dev-3fb3ed8` (the CI's builds off the default branch) | never listed nor the latest; its own `/play/` and `/file/` links and the Admin API (`channel` filter) |

Every release in the catalog API and the Admin API carries its `channel`. A pre-release goes out the
usual way: put the version (`1.3.0-beta.1`) in the source and push, or tag `v1.3.0-beta.1`.

**Development builds** pile up, one per branch and version. `WarpEngine::DevReleasePruneJob`
removes the ones superseded on their branch and the ones not updated for `dev_release_ttl_days`
(default 30), assets and release folder included. The newest build of a branch in
`dev_release_keep_branches` stays whatever its age — a long-lived working branch such as
`develop`:

```ruby
WarpEngine.configure do |config|
  config.dev_release_ttl_days = 30
  config.dev_release_keep_branches = %w[develop]
end
```

The engine does not schedule the job; run it with your job backend, e.g. a Solid Queue recurring
task in `config/recurring.yml`:

```yaml
production:
  prune_dev_releases:
    class: WarpEngine::DevReleasePruneJob
    schedule: every day at 4am
```

`rake warp_engine:releases:prune_dev` does the same by hand (`TTL_DAYS` overrides the setting,
`DRY_RUN=1` only lists).

**Pull request previews.** With a forge configured, the publish of a development build adds a
comment to the open pull request of its branch (the software's pipeline names the repository):
the version, the commit, the play link and every download. The next build of the branch changes
the same comment. The forge token needs the `write:issue` scope for it; without it the job logs
the refusal and the publish goes on.

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

## File layout

Every release has its own folder in `file_container_path`, `<name>/<version>/`:

```
mygame/1.2.0/mygame-1.2.0.metadata.json
mygame/1.2.0/mygame-1.2.0.html.zip
mygame/1.2.0/mygame-1.2.0-win-x64.zip
mygame/1.2.0/html/index.html          # the html zip, unpacked
mygame/1.2.0/docs/                    # the docs zip, unpacked
_runtimes/emulatorjs-4.2.3/           # the installed runtimes
shelves/C64/                          # the outlets' folders
```

The uploads keep their names, so a download is still called
`mygame-1.2.0-win-x64.zip`; a kind the engine unpacks becomes a folder named after
the kind. `POST /build/upload` writes into the folder and refuses a software name
that is one of the root folders the engine keeps for itself (`_runtimes` and the
first folder of every outlet path, `WarpEngine::ReleaseLayout.reserved`).

Before 3.4 the container was flat (`mygame-1.2.0.prg`, `mygame-1.2.0/` for the
html build, `mygame-1.2.0-docs/`). `bin/rails warp_engine:files:restructure`
(`DRY_RUN=1` only lists) moves such entries into their release's folder and points
the asset and download records at the new paths; an entry no release owns stays
where it is and is listed. The old URLs keep working: `GET /file/<old path>`
answers 301 with the new place, and `GET /api/download?path=<old path>` serves the
file from it.

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

## Runtimes

A runtime is what a release plays in on the web: EmulatorJS, the TIC-80 player, a
host's own. The engine keeps each version of it **once**, under
`_runtimes/<name>-<version>/` of the file container, and renders the player page
of a release from the runtime's template and the release's own asset (usually the
cartridge) at `GET /play/<name>/<version>`. The release needs no `html` build of
its own; a fix in the runtime reaches every release, and a browser caches the
runtime's files once for all of them (they are served `immutable` for a year).

A runtime knows nothing of platforms. **A platform binds to a runtime**, with the
parameters it needs, and the binding is many-to-many: EmulatorJS serves the C64
and the Plus/4 (and any platform with a libretro core), and a platform may offer
more than one runtime, one of them the default.

| Builtin runtime | Files come from | Bound by |
|---|---|---|
| `emulatorjs` | downloaded from `cdn.emulatorjs.org`, SHA-256 checked per file (`lib/warp_engine/runtime/checksums/`), cores as components | `c64` (`vice_x64sc`), `plus4` (`vice_xplus4`), `dos` (`dosbox_pure`, isolated) |
| `tic80` | uploaded by a build (`POST /build/runtime`): the player of a TIC-80 Pro build | `tic80` |

### Installing

```sh
bin/rails warp_engine:runtimes:install            # every downloaded runtime, the cores the platforms need
bin/rails warp_engine:runtimes:install NAME=emulatorjs COMPONENTS=core:vice_x64 DRY_RUN=1
bin/rails warp_engine:runtimes:list               # versions, components, size, releases bound
bin/rails warp_engine:runtimes:verify             # every file against its SHA-256
```

Run `install` after every deploy (it only fetches what is missing; installed files
never change). An uploaded runtime arrives from its build:

```sh
curl -fsS -H "X-Update-Secret: $TOKEN" -F name=tic80 -F version=1.1.2837 \
     -F file=@tic80-runtime.zip https://games.example.org/build/runtime
```

The zip's declared files are taken (others ignored); the same version again with
the same files answers 200, with other files 409.

### Choosing and binding

```ruby
WarpEngine.configure do
  runtime :emulatorjs, version: "4.2.3"          # the version new releases bind to (default: the newest)

  platform_web :c64, :emulatorjs, as: :fast, core: "vice_x64"   # a second binding
  platform_web :c64, :fast, default: true                       # make it the default
  platform_web :plus4, :emulatorjs, enabled: false               # switch one off

  register_platform "amiga" do
    kind :cartridge, ext: ".adf", required: true
    libretro "puae", name: "PUAE"                                # the platform's libretro core
    web :emulatorjs, core: :libretro                             # bind a platform of your own
  end

  register_runtime "ruffle" do                                   # a runtime of your own
    label "Ruffle"
    source :upload
    files "ruffle.js", "*.wasm"
    template Rails.root.join("runtimes/ruffle.html")
  end
end
```

A platform's libretro core is declared once, with `libretro` (the builtin ones:
`c64` `vice_x64sc`, `plus4` `vice_xplus4`, `dos` `dosbox_pure`, `tic80` `tic80`).
A web binding takes it with `core: :libretro`, the RetroArch store engine's config
boots the platform's playlist with `<core>_libretro`, and `GET
/build/platforms/:name` lists it under `libretro`: the browser and RetroArch run a
release on the same core.

A DOS program plays from its cartridge zip as it is: the page appends a
`start.conf` to the zip in the browser (DOSBox Pure takes a `.conf`), copies the
program folder to `C:\APPS\` (where WEDOS installs it; the binding's
`dos_root`) and starts `web.start` from `metadata.json`, or else the folder's
`.BAT`, `.COM` or `.EXE`, in that order.

A binding may say `isolated: true` when its runtime needs `SharedArrayBuffer` (a
threaded core): the page is then served with `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy`. A template is plain HTML with `{{ title }}`
(escaped) and `{{ json params.core }}` (JSON for a script) placeholders; it sees
`title`, `name`, `version`, `payload_url`, `runtime_url`, `isolated`, `params` and
`start`.

### Publishing and playing

A publish binds the release to the platform's default binding in the runtime
version the host chose, when that version is installed with the components the
binding names; otherwise the release stays unbound and plays (if at all) from its
`html` asset. `metadata.json` may steer it:

```json
{ "web": { "runtime": "fast", "params": { "options": { "keyboardInput": "enabled" } }, "enabled": true } }
```

`enabled: false` keeps a release off the web, its `html` folder too. The catalog API gives every release
`playUrl` (its runtime page, else its `html` folder) and `players` (every binding
it can play in now, with its URL: `/play/<name>/<version>/<binding>`).

### Moving releases

```sh
bin/rails warp_engine:runtimes:migrate DRY_RUN=1       # bind releases that play from an html folder holding the runtime bit for bit
bin/rails warp_engine:runtimes:migrate UNPLAYED=1 PLATFORMS=dos EXCLUDE=we-dos,ttgwiki   # and the ones that never played on the web
bin/rails warp_engine:runtimes:prune_html DRY_RUN=1    # then drop those html folders and zips
bin/rails warp_engine:runtimes:rebind NAME=emulatorjs FROM=4.2.3 TO=4.2.4
bin/rails warp_engine:runtimes:gc DRY_RUN=1            # versions no release uses
```

`migrate` recognises the version by the files' digests, never by a guess: a
folder that holds no installed version bit for bit is skipped and reported.

SysInfo shows a *Runtimes* group (version, source, components needed and
missing, platforms, size, and the file check among the live checks), a *Plays on
the web in* line per platform, and a *Runtimes* number on the catalog strip; the
admin has a *Runtimes* page and the Admin API a `runtimes` resource.

## Outlets

An outlet is a format the catalog leaves the engine in. Three layers make up the way
out:

```
outlets      wecp (/api, always on, served)   shelf (folders, materialized)   assembly64 (/leet/search, served)
offer          — (per caller: SoftwareService)  WarpEngine::Catalog::Offer — which titles, which release, which file
models/seams Software, Release, ReleaseAsset · Storage, AccessPolicy, Images, DownloadService
```

Every type has the same shape. `lib/warp_engine/outlets/TYPE.rb` holds the outlet
class: it reads and checks its options, describes itself for `GET /api/service`, and
draws its routes (served) or syncs (materialized). The objects that do the work live in
the folder beside it and take the outlet: `Shelf::Builder` (with `Shelf::IndexFile`,
`Shelf::Layouts`, `Shelf::Preview`) and `Assembly64::Catalog` (with `Assembly64::Query`).
A served type's controller lives in `app/controllers/warp_engine` — the catalog API's
under `api/`, the others' under `outlets/`. Names and texts written for small machines
(`WarpEngine::Names`) are shared, so a title reads the same on a shelf and on Assembly64.

- **`wecp`**, the WarpEngine Catalog Protocol: the JSON API under `/api` and the files
  under `/file`, drawn by `WarpEngine::Outlets::Wecp.draw_routes`. Always on, never
  configured, and the only outlet that knows a caller — sign-in, entitlements and gated
  titles live here —, so it alone has no `Catalog::Offer`. (The build and CI endpoints
  under `/build` and `/api/builds`, `/api/ci` are the way in, not an outlet.)
- **`shelf`**: a folder with an `INDEX.TXT` (below). *Materialized*: rewritten whenever
  the catalog changes.
- **`assembly64`**: the Assembly64 search API (below). *Served*: answers requests.

Every outlet but `wecp` offers what an anonymous caller may have without a gate: the
kept titles of its platforms with a listed status, each with the latest release that
has the asset (`WarpEngine::Catalog::Offer`). So a shelf and an Assembly64 server list
the same titles, and a change to that rule changes both.

```ruby
shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG"   # = outlet :c64, type: :shelf, platform: "c64", ...
outlet :assembly64, type: :assembly64, platforms: %w[c64], hosts: %w[a64.example.org],
                    repo: "acme", repo_name: "Acme Games"
```

Every outlet, shelves included, is kept in `config.outlets` under its key. `GET
/api/service` lists them under `outlets` (`key`, `type`, `platforms` and what the type
adds). The configuration is checked at boot: an unknown type, option, platform or kind,
two outlets with one key, or what the outlets of a type must agree on (two shelves in one
folder) stops the application.

```sh
bin/rails warp_engine:outlets:check   # every outlet and what it offers (STRICT=1 fails on anything left out)
bin/rails warp_engine:outlets:sync    # rewrite every materialized outlet (DRY_RUN=1 only says what would change)
```

The Admin API (and its MCP tools) has the same view: `GET /outlets` lists the outlets
(the descriptor, `description`, `materialized`, `served`), `GET /outlets/:key/check`
what one offers (`items`) and leaves out (`skipped`, with the reason); both answer 409
while the configuration is invalid.

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
platform, by a `WarpEngine::OutletRefreshJob` in the host's ActiveJob queue; one that
fails is logged and does not fail the save.

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

A download through the outlet is logged with the outlet's key (`outlet`) and the
caller's `Client-Id` (`client_id`), so the statistics tell the Ultimate's downloads
from the catalog API's: the admin's *Download Stats* shows and filters both, the Admin
API's `GET /downloads` takes `outlet` (exact; `none` for the catalog API) and
`clientId`.

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
shelf :dos, key: :apps, kind: %w[cartridge win_x86], layout: "folders", path: "shelves/APPS",
            urls: [ "ftp://ftp.example.org/APPS" ]
```

A shelf is an outlet of the type `shelf` (`WarpEngine::Outlets::Shelf`), keyed by its
platform unless `key:` names another.

| Key | |
|---|---|
| `platform` | whose titles go on the shelf |
| `kind` | which asset of the release (`ReleaseAsset` kind), or a list of them |
| `layout` | `flat` (default): one file a title; `folders`: one folder a title (below) |
| `path` | the folder, relative to `file_container_path` |
| `extension` | `flat` only: the extension on the shelf, in capitals; a title whose file has another one (a `.d64` on a `.PRG` shelf) is left out |
| `name_length` | the longest file name, extension included (default 16); for `folders`, the longest folder name (default 8, as DOS has it) |
| `statuses` | optional; without it, the statuses whose `default_visible` is set |
| `urls` | optional: where the host serves the folder (`ftp`, `http`, `https`) |
| `preview` | optional, `flat` only: a picture of each title beside its file (`c64`, below) |

The configuration is checked at boot: an unknown platform, kind or layout, a path outside
the container, two shelves in one folder, a URL without one of those schemes, or a storage
adapter other than `:local` stops the application rather than leaving a shelf empty.

**Serving it is the host's.** The engine writes the folder; it runs no FTP or HTTP server
of its own. A host points its servers at the folder and names their addresses in `urls`,
which `GET /api/service` lists with the shelf's outlet under `outlets` — so a page or a
client can say where a shelf is. A machine that cannot speak HTTPS cannot ask the API, so a client for one keeps
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
WE64.PRG|1.0.0|31816|5e1d0c3b|WE64|Teletype Games|The store on the C64.|tool|WE64.PVW
```

`crc32` is zlib's, in hexadecimal. `category` is the software's category key (empty for
none), `preview` the name of its picture on the shelf (empty for none). Text is
transliterated to ASCII, `|` and line breaks become spaces, and a line is at most 255
bytes — the description is what gets cut. Version 1 of the format (1.2–1.9) ended after
the description; the two fields came after it so that a version 1 reader still reads a
version 2 line right.

**Previews.** A flat shelf with `preview: "c64"` also holds `NAME.PVW` beside `NAME.PRG`
for every title with an image in its gallery (the default one, else the first): a C64
bitmap a client can put on the screen as it comes (`WarpEngine::Outlets::Shelf::Preview::C64`),
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

**A `folders` shelf** holds a folder for each title and kind, the layout WEDOS reads:
the asset is a zip with the folder at its top, and the platform's service names the folder
from the release's uploaded metadata (`shelf_folder(metadata, kind)`; on `dos` the `dos`
block: `folder` for the `cartridge`, `win32_folder` for `win_x86`). The engine unpacks the
folder without its `settings` files, so an update never overwrites an installed program's
configuration, and writes two files into it:

```
shelves/APPS/
  INDEX.TXT
  WEDOS/  WEDOS.EXE  README.md  LICENSE  INFO.INI  FILES.LST
  WEDOSW/ WEDOSW.EXE README.md  LICENSE  INFO.INI  FILES.LST
```

- `INFO.INI`: `[program]` with `name`, `description`, `version` and `platform` (`DOS` or
  `WIN32`), CRLF line ends;
- `FILES.LST`: `crc32 size path` for every file but itself, sorted, CRLF line ends, which
  the client checks its downloads against.

A title without the metadata, or with a folder name that does not fit, is left off and
reported. `INDEX.TXT` lists the folders as a flat shelf lists files (its name has a dot,
so WEDOS does not take it for a program). A folder is built next to the old one and
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
bin/rails warp_engine:outlets:check            # what each shelf holds and leaves out (STRICT=1 fails on the latter)
bin/rails warp_engine:outlets:sync             # rebuild every shelf (every materialized outlet)
DRY_RUN=1 bin/rails warp_engine:outlets:sync   # only say what would change
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

## Store engines

`batocera` and `retroarch` are platforms whose releases are store engines: the
program that puts this catalog's games on a Batocera box or into RetroArch's
library (`we-batocera`, `we-retroarch`). A release is one `.tar.gz` (the
`cartridge` kind) holding the engine, the shared core and the engine's own
`install.sh`; the `store_engine` pipeline runs the repository's
`scripts/ci-test.sh` and `scripts/pack.sh` (which writes `dist/release.tar.gz`)
and releases on tags.

The catalog serves each of them, publicly, under `/api/stores/<client>/`:

| Path | What |
|---|---|
| `install.sh` | the installer: downloads the release the machines run and runs its `install.sh` with the store config below |
| `config.json` | the store config: this catalog, the store's name and id, the folder, the statuses it installs, the logo, the platforms the engine has, and `store.api.release` |
| `release` | `{ software, version, url, size }`: the release the machines run |

An installed engine reads `release` at the start of every sync; when the
version differs from its own it downloads the archive, checks its size, moves
the new engine and core over the installed ones and carries on in the new
engine. The release is the newest stable one with its archive, unless the host
pins a version — a rollback for every machine at once.

What the host sets per store engine is a `WarpEngine::StoreClient` (the *Store
Engines* admin page, or the Admin API's `store_clients`, which the MCP server
offers too): the catalog software it is released as (default
`we-batocera` / `we-retroarch`), the store's name (default `store_name`, else the
host), its id and subfolder (default from the host name), the statuses (default:
those shown by default), the logo (http(s) URLs ending in `.png` or `.svg`) and
the pinned version. A blank field takes the default.

## Store registry

`GET /api/stores` is the registry the [WarpEngine Desktop](https://wiki.teletypegames.org/stores/we-desktop)
reads on its first run: which catalogs it can install. A record is a name and a catalog
address and nothing else — how a store behaves is fixed in each installed client:

```json
[ { "name": "My Studio", "catalogUrl": "https://games.mystudio.example" } ]
```

By default the list is this catalog alone, under `store_name` or, without it, the host
name of its address. So a client built for your catalog (`make dist STORES_API=https://games.mystudio.example/api/stores`,
or a branded build, which reads its catalog's registry on its own) offers your store and
nobody else's. `GET /api/service` names the registry's address under `stores`, and the
SysInfo page shows which registry is in use.

```ruby
store_name "My Studio"

# a fixed list; :own stands for this catalog
store_registry [ :own, { name: "Friends' Games", catalog_url: "https://friends.example" } ]

# the host's own records: an object answering stores(catalog_url:) with
# WarpEngine::StoreRegistry::Entry objects or name/catalog_url Hashes
store_registry StoreDirectory.new

# no registry: GET /api/stores answers 404, /api/service reports stores: null
store_registry :none
```

Records without a name or an http(s) catalog address are left out. The endpoint is
public: a client has nobody to sign in as before it has a store.

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

### Tool sign-in

An editor extension or a script needs an Admin API token, not a catalog one, and it
needs no person identity from the host: it asks for Admin API scopes, and an
administrator approves it in the admin.

1. the tool `POST`s `/api/auth/device` with `scopes[]` (`admin:read`, `admin:write`,
   `admin:tokens`) and shows the `userCode`;
2. an administrator opens `verificationUrlComplete` — by default the admin's
   *Tool Sign In* page (`/admin/tool_sign_in?code=…`; `tool_verification_url` moves it),
   sees the tool's name and the scopes, and approves or denies;
3. the tool polls `POST /api/auth/device/token` as above and gets a token with the
   scopes it asked for, owned by the approving administrator.

A tool sign-in works wherever the Admin API is enabled; it needs no
`access_token_owner_class`. A scope outside the Admin API ones answers 422.

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
  payload[:source]    # :ci, or :sync when another engine pushed it (4.5)
end
```

Hosts that must support older engine versions can feature-detect with
`WarpEngine.respond_to?(:instruments_publish?) && WarpEngine.instruments_publish?`.

Downloads emit one too — `warp_engine.download`, with `path`, `asset`,
`release`, `software`, `subject` and the `Download` record — so a host can keep
its own account of who fetched what without reaching into `DownloadService`.

## Sync

Engines copy releases to one another (4.5; peers, directions and transports since
5.0). Each partner is a `WarpEngine::SyncPeer` (admin: *Sync Peers*; Admin API:
`sync_peers`), and sync runs in two directions, each switched on and filtered on its
own in the initializer:

```ruby
WarpEngine.configure do
  sync do
    events true                         # false, true or :verbose
    event_retention_days 90

    outbound do                         # this engine pushes its releases to its peers
      enabled true
      software_switch :opt_out          # false (default), :opt_out or :opt_in
      allowed_softwares  %w[blessingofra* thread-of-ariadne]
      denied_softwares   %w[*-test]
      allowed_categories %w[game demo]
      denied_categories  %w[tool]
      allowed_platforms  %w[c64 plus4 dos]
      denied_platforms   %w[electron]
      allowed_statuses   %w[released]
      denied_statuses    %w[development]
      allowed_kinds      %w[cartridge html docs]
      denied_kinds       %w[win_x64 mac_universal]
      allowed_channels   %w[stable]     # the default
      timeout            120            # seconds per request
    end

    inbound do                          # its peers may push their releases here
      enabled true
      allowed_platforms  %w[c64]
      denied_softwares   %w[*-test]
      allowed_channels   %w[stable]     # the default
      protect_local      true           # the default: sync never overwrites what our CI published
    end
  end
end
```

Both directions are off by default.

### Peers

A peer record describes both sides of one partnership:

- **outbound** (`outbound_enabled`): how its releases reach it — its `transport`
  (`http` by default), the transport's `transport_options` (`host` for `http`) and its
  `secret` (for `http`: the token the other engine issued for us), stored encrypted with
  a key derived from `secret_key_base`;
- **inbound** (`inbound_enabled`): the `sync` token this engine issued to it (*Issue
  inbound token* on its page, `POST /sync_peers/:id/inbound_token`, or
  `rake "warp_engine:sync:inbound_token[label]" FILE=…`), owned by the peer. It is shown
  once; the other engine stores it as the secret of the peer that points back here.

A `sync` token opens `POST /build/upload`, `POST /build/publish`, `POST /build/images` and
`DELETE /build/release` only, is always `unrestricted`, belongs to a peer and is never written to a pipeline. The
receiving side needs `application_tokens from: :database`.

A peer may narrow the outbound channels for itself (5.3, `allowed_channels`, the admin's
*Channels pushed to it*, `allowedChannels` in the Admin API): empty, it takes every channel
the global `outbound { allowed_channels }` lets go; filled, only those of them — it never
widens the global list. A release it holds back says so: *the beta channel is not in
Studio's channels*.

### Removals

A release soft-deleted here (the admin, the Admin API, the dev-release cleanup) is
removed on every outbound peer that would have got it: a `WarpEngine::SyncRemovalJob`
asks the peer's transport, logged as an outbound `remove` event. A soft-deleted
software goes the same way, without a version. What came here by sync is not passed
along. The `http` transport sends `DELETE /build/release?name=&version=` (no
`version`: the software); `rsync` carries no removals and logs the event `skipped`.

The receiving engine removes only what that peer pushed there (`origin` `sync` and its
`sync_peer_id`): never a release its own CI published or another peer pushed (409), and
the software too once no release of it is left. Nothing of it there is a 404, which the
sender logs as `skipped`.

### Pairing (5.3)

Instead of an administrator adding the peer and handing its token over, the engine that
wants to push may pair by itself through the Admin API's `sync_pairings` resource:

```ruby
WarpEngine.configure do
  sync do
    inbound do
      enabled true
      pairing :anyone   # default :admin
    end
  end
end
```

With `pairing :anyone` every tool sign-in approved here gets the `sync:pair` scope beside
the ones it asked for. That scope opens `sync_pairings` and nothing else: `POST
/sync_pairings { label }` adds an inbound-only peer owned by the caller (`created_by`) and
answers its token once (`plainToken`); `GET`, `PATCH` (the label), `POST
/sync_pairings/:id/token` (a new token, the old one stops) and `DELETE` (soft, the token is
revoked) reach only the caller's own peers. An `admin:write` token may always pair. Pairing
gives no more than the `inbound` lists allow anyway; while inbound is off the resource
answers 409. The WarpEngine Toolbox pairs a local engine with a remote one this way, then
adds the outbound peer on the local side with the token.

### Outbound

After every publish of a release this engine made itself, the release goes to every peer
that takes outbound pushes, through `WarpEngine::SyncPushJob` on the host's job backend.
A release goes when:

1. its channel is in `allowed_channels` (only `stable` by default);
2. the per-software switch lets it (`software_switch :opt_out`: every software
   unless switched off on its admin page; `:opt_in`: none unless switched on);
3. neither its name (`*` wildcards) nor its category, platform or status is in
   a `denied_*` list;
4. on every axis with an `allowed_*` list it matches: the name *or* the
   category, the platform, the status. A software without a category or status
   matches no list of that axis.

The kind lists do not hold a release back; they choose its files. A platform's
required kinds always go. The files are the ones the CI uploaded, still in the release's
folder, plus `name-version.metadata.json` (`WarpEngine::Sync::Package`); a file missing
under its own name (a software renamed since) comes from the path its release asset
records, and an unpacked kind whose zip is gone is zipped again. A peer that does not
answer is tried again, five times in all; a refusal on purpose (403: its inbound settings,
409: a newer or its own version) is logged as skipped, not as an error.

The images follow (5.3): once a release went through a transport that carries images
(`images?`: `http` and `rsync`), the software's gallery goes after it, and after every
change of a gallery (the `warp_engine.software_images` notification, a few seconds later
through `WarpEngine::SyncImagesJob`) it goes on its own to the peers its newest release
would go to. Over `http` the gallery is a manifest of SHA-256 digests (`POST /build/images`):
the other side keeps what it has, names what it lacks, those files follow one by one (`POST
/build/images/upload`), then the manifest is applied — order, default image, and the images
it got by sync before and the manifest no longer has are unlinked. The images came by sync
get `origin` `sync` and are not sent on. Over `rsync` the gallery is mirrored into
`<path>/<name>/images/` with an `images.json` manifest.

### Inbound

A push with a peer's token is taken only while `inbound` is on, the peer is kept and
`inbound_enabled`, and the release passes the inbound lists: the name and channel when
a file is uploaded, the platform, category (from the uploaded metadata) and status at the
publish. A refusal answers 403 with the reason. With `protect_local` (the default) a
version this engine's CI published is not overwritten (409). The release is published
with `origin` `sync` and its `sync_peer`, so it is never pushed on: two engines may
push to each other.

A gallery push is taken while the peer may push here, the software is here (409 before
its first release) and some release of it passes the inbound lists. With `protect_local`
a gallery somebody set here (an image with `origin` `local`: the admin, the Admin API) is
left alone (409); changing a synced image here makes it `local`.

### Transports

How a package reaches a peer is its transport, a `WarpEngine::Sync::Transport`. The
engine ships two:

- `http` (`WarpEngine::Sync::Transports::Http`): another WarpEngine's `/build`
  endpoints; what it has is read from its public `GET /api/softwares/:name/builds`.
  Options: `host`, and the `token` it issued for us as the secret.
- `rsync` (5.1, `WarpEngine::Sync::Transports::Rsync`): a file mirror over SSH, no
  catalog on the other side. A release lands in `<path>/<name>/<version>/` with the files
  the CI uploaded and `<name>-<version>.metadata.json`; files already there are
  replaced, others left alone; what is there is read with `rsync --list-only`. Options:
  `host`, `port` (22), `user`, `path` (must exist), `host_key` (a known_hosts line; empty
  takes the key the host shows first) and the private key (OpenSSH, no passphrase) as the
  secret. The host image needs the `rsync` and `ssh` programs (Debian: `rsync
  openssh-client`). A transport
names itself (`key`, `label`), describes its settings (`options`: the admin draws the
peer form from them) and implements `check`, `existing` and `deliver`. A host registers
its own:

```ruby
WarpEngine.configure do
  register_sync_transport :rsync, "MyStudio::RsyncTransport"
end
```

### Running it by hand

A new peer only gets the releases published after it was added. What it may be missing
is sent by hand, in one of two modes: the newest allowed release of each software, or
every allowed release, oldest version first (a *full sync*). A run either applies the
configured outbound filters or leaves them out (then every software goes with every kind
of file), sends the channels it is given, can be narrowed by software names, platforms,
categories and statuses (`WarpEngine::Sync::Criteria`), and by default skips what the
peer already has (the transport's `existing`). Releases that came by sync are never sent.

- **Sync Runner** (admin page): peers, mode, channels, filters on or off, narrowings;
  *Preview* lists what would go and what is held back, *Run* queues the pushes.
- **A peer's page**: *Check connection*, *Push latest releases*, *Full sync*, a link to
  the runner.
- **A software's page**: its state per peer and direction, why its newest release would
  not go, *Push now*, its events. A release's page shows its origin and events.
- **Admin API**: `POST /sync_peers/:id/push`, `POST /sync_peers/run` (`peerIds`), with
  `all`, `filtered`, `channels`, `softwares`, `platforms`, `categories`, `statuses`,
  `skipExisting` and `dryRun`; `GET /softwares/:softwareId/sync_status` and
  `GET /softwares/:softwareId/sync_events`.
- **rake**:

```bash
bin/rails "warp_engine:sync:push[other-engine]"                # newest allowed release of every software
bin/rails "warp_engine:sync:push[other-engine,mygame]"         # of one software
ALL=1 bin/rails "warp_engine:sync:push[other-engine]"          # full sync
ALL=1 FILTERED=0 CHANNELS=stable,beta bin/rails "warp_engine:sync:push[other-engine]"
PLATFORMS=c64,plus4 DRY_RUN=1 bin/rails "warp_engine:sync:push[other-engine]"
FORCE=1 ALL_PEERS=1 bin/rails warp_engine:sync:push             # every outbound peer, send again what they have
bin/rails "warp_engine:sync:check[other-engine]"               # does the other side take us
FILE=/run/secrets/token bin/rails "warp_engine:sync:inbound_token[other-engine]"
```

With `events` on, every push and every inbound publish is a `WarpEngine::SyncEvent`, linked
to its peer, software and release (admin: *Sync Events*; Admin API: `sync_events`);
`:verbose` logs the releases a filter held back too. `WarpEngine::SyncEventPruneJob`
deletes the events older than `event_retention_days`; the engine does not schedule it,
add it to the host's recurring tasks (or run `rake warp_engine:sync:prune`).

Sync copies releases, nothing else: deleting a release, editing a software in the
admin, its images and the runtimes are not carried over.

## Forks

Anyone may make their own version of a game: the developer tools clone the
software's source repository, give it a new name and a new `origin`, and
connect it to an engine of the forker's choice. The engines link the fork and
its parent.

**The source.** An external link has a `kind`: `link` (a page) or `source`
(the git repository; at most one per software, with an optional `ref`). The
metadata's `repo` becomes the source, and so does the repository a scaffold
creates. `WarpEngine::SourceVerifyJob` runs `git ls-remote` with every
credential turned off and stores whether the source is `public`; the engine
needs `git` for it. A software is offered for forking (`forksAllowed` in the
catalog) when its `forks_allowed` switch is on (the default) and its source is
public.

**A fork's parent** comes in the metadata, flat so a Lua header can carry it
too (a tic80 repo may also keep a `metadata.json` beside its header: its keys, `web`
and a nested `fork_of` among them, win over the header's): `fork_of_engine` (the parent engine's base URL), `fork_of_name`, and
optionally `fork_of_version` and `fork_of_repo`; a JSON metadata may nest them
as `fork_of: { engine, name, version, repo }`. `forks_allowed: false` turns
forking off.

**Linking engines.** After a fork is published, the engine tells the parent's
engine (`POST <parent>/api/forks` with its own URL and the fork's name) — only
when it announces, is not a local engine and has a public address. The parent
reads the fork back through the child's `GET /api/software` and records it as a
`WarpEngine::ForkLink` only when the fork really names one of its softwares; it
waits as `pending` for an administrator (*Fork Links* in the admin, or
`fork_links` in the Admin API) unless the moderation is `:auto`, and
`warp_engine.fork_announced` (with `fork_link` and `software`) is instrumented
so the host can tell someone. `WarpEngine::ForkRecheckJob` verifies the links
again and marks the vanished ones `gone`.

```ruby
WarpEngine.configure do
  forks do
    engine_url "https://games.example"   # default: site_url
    announce true                        # tell parents about our forks
    accept_announcements true            # take announcements of forks of ours
    moderation :pending                  # or :auto
    denied_engines %w[spam.example]
    # announcements_per_hour 30, recheck_days 7, timeout 15
    # allow_private_engines true         # two engines on one machine, for trying it out
  end
end
```

Schedule the checks with your job backend, e.g. Solid Queue's `config/recurring.yml`:

```yaml
warp_engine_source_verify:
  class: WarpEngine::SourceVerifyJob
  schedule: every day at 4am
warp_engine_fork_recheck:
  class: WarpEngine::ForkRecheckJob
  schedule: every day at 5am
```

## Public API

| Endpoint | Purpose |
| --- | --- |
| `GET /api/service` | What this deployment is: version, whether the catalog gates, how to sign in (or that you cannot), and its outlets (shelves with their addresses among them) |
| `GET /api/software` | The catalog with releases, assets, links, download counts, an optional `category` and an `access` block — whole, or one page at a time; see *Paging and filters* |
| `GET /api/software/facets` | How many softwares each status, platform and category would show under the other filters |
| `GET /api/software/vocabulary` | The statuses and categories this catalog uses, with labels and display order |
| `GET /api/software/highlighted` | The currently highlighted title |
| `GET /api/builds` | Expected asset kinds per platform (build matrix) |
| `GET /api/softwares/:name/builds` | Actual vs. missing build assets per release |
| `GET /api/softwares/:name/forks` | The forks of a software: its children here and the announced forks an administrator let through; see *Forks* |
| `POST /api/forks` | Another engine announces a fork of one of our softwares (404 unless `accept_announcements`); see *Forks* |
| `GET /api/image/:id` | Serves images — **the host's endpoint**, see *Images* |
| `GET /api/download?path=` | Serves an artifact and logs a download record |
| `GET /file/*path` | Serves static build output (web-playable games, docs) |
| `POST /api/auth/device` | Starts a device sign-in; returns the code pair (404 without a client identity) |
| `POST /api/auth/device/token` | Polls a device sign-in for its token |
| `DELETE /api/auth/token` | Revokes the bearer token on the request (signing out) |

Each release lists its assets as `kind` and `path`; an asset of a download-only kind
(the `cli_*` kinds) also has `"launch": false`, which a client reads as "install it, do
not start it". The envelope's `api` is 4 since this flag.

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
theme and the `/admin` routes. WarpEngine appends its resource files to
`ActiveAdmin.application.load_paths` and registers its own stylesheet and script
(`warp_engine/admin.css`, `warp_engine/admin.js`: the file manager, its picker
for release-asset paths, the quick links), so its pages work in any host. They
are under the menu parent `WarpEngine`, use no emoji (icons are inline SVG from
`WarpEngine::AdminIcons`) and take their colors from the host theme's
`--c-*` custom properties (RGB triplets, as `--c-accent: 21 128 61`), with light
defaults when the host defines none — a host theme that switches those for dark
mode switches the engine's pages too. What to copy into a new host:

- if you generate apipie docs, add
  `"#{WarpEngine::Engine.root}/app/controllers/**/*.rb"` to your
  `api_controllers_matcher`;
- on **ActiveAdmin 4**, which has no stylesheet and script registry, link the two
  files yourself: copy ActiveAdmin's `app/views/active_admin/_html_head.html.erb`
  into the host and add

  ```erb
  <%= stylesheet_link_tag "warp_engine/admin" %>
  <%= javascript_include_tag "warp_engine/admin", defer: true %>
  ```

  after its `active_admin` stylesheet. Without them the pages work, but the file
  manager and the asset path picker are unstyled and without their script.

**SysInfo (1.13, a tree since 2.1).** The *WarpEngine → ℹ️ SysInfo* page shows the
engine as it runs, as one tree: engine, publishing, adapters, client sign-in, CI, platforms,
outlets, Admin API and additional resources, every line with a status — *error* (needs
fixing), *warn* (works, with a catch), *ok*, *info* and *off* (switched off on purpose) —
and a branch takes the worst below it. Branches with a problem open by themselves; the
page counts each status (a click shows only the problems), searches labels and values,
expands or collapses everything and remembers what was open. Above the tree the catalog
in numbers: softwares by status, releases, downloads today and in 30 days, outlets.
It is computed on every request (`WarpEngine::SysInfo`, the tree as `#tree` of
`SysInfo::Node`), secrets show only as *set* or *not set*, and the page brings its own
styles, so it looks the same in any host.

**Live checks.** The page asks the CI server who its API token belongs to (`ping` of
the CI adapter: `GET /api/user` on Woodpecker, `GET /api/v4/user` on GitLab, 3 s to
connect, 5 s to answer) and shows the answer, or the error, with its time. A switch
on the page turns them off for one view (`?live=0`); the host turns them off for good:

```ruby
WarpEngine.configure do
  sys_info_live_checks false
end
```

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


### The reference on SysInfo (4.8)

While the Admin API is on, the SysInfo admin page has an *Admin API reference*
section below the configuration tree: the OpenAPI document drawn by the engine's
own template (`WarpEngine::ApiReference`), in the admin's look, light and dark.
Operations are grouped by resource and filterable; each one opens to its
parameters, request body, success response and errors, the scope it needs and a
`curl` line to copy. Types link to the schemas, listed at the end. Nothing is loaded
from outside.

The *Admin API* group of SysInfo links `openapi.json`, the docs page (`docs_ui`)
and, while the document is public (`public_openapi`), the host's page that shows it
to everyone:

```ruby
admin_api do
  enable
  public_openapi
  docs_ui
  public_docs_url "/api/swagger?spec=Admin%20API"
end
```

## Local engines and `/.well-known/warp-engine` (5.2)

`GET /.well-known/warp-engine` (public) tells a developer tool what answers at an
address before it signs in:

```json
{ "engine": "warp-engine", "version": "5.2.0", "api": 2, "name": "Local",
  "profile": "local", "signIn": ["token-file"], "adminApi": "/api/admin/v1",
  "admin": false, "sync": { "inbound": false, "target": "https://games.example.org" } }
```

- `profile` — `server` (the default: a catalog people sign in to with the tool sign-in) or
  `local` (one developer's machine; the tool reads a token file instead);
- `adminApi` — the Admin API prefix, `null` when it is off; `admin` — whether an ActiveAdmin
  UI is loaded;
- `sync.inbound` — whether this engine takes syncs; `sync.pairing` (5.3) — who may pair
  (`admin`, `anyone`, `null` while inbound is off); `sync.features` — what this engine's
  sync knows (`peer-channels`, `images`, `pairing`); `sync.target` — the engine this one means
  to sync to, so a tool can offer the pairing.

```ruby
WarpEngine.configure do
  profile :local
  sync_target "https://games.example.org"
end
```

[engines/warp-engine-local](https://git.teletypegames.org/engines/warp-engine-local) is such a
host: one container, SQLite, a token file, the admin web UI optional.

### Local components: a git server and CI beside the engine (5.4)

A local engine can start a git server and a CI next to itself and wire them in, without a person
signing in anywhere:

```ruby
WarpEngine.configure do
  local_components do
    enable
    engine_url "http://warp-engine-local:7470"   # where the components reach this engine
    forge_port 7471                               # the git server on 127.0.0.1
  end
end
```

The engine talks to the Docker Engine on its socket (`/var/run/docker.sock`, mounted into its
container; `WarpEngine::Local::Runtime::Docker`, no gem needed) and runs each
`WarpEngine::Local::Component` in labelled containers on one network (`warp-local`):

| Component | Role | Containers | Set-up |
| --- | --- | --- | --- |
| `gitea` | `forge` | `warp-local-gitea` (Gitea 1.27.3, 127.0.0.1:`forge_port`) | an administrator, the `games` organisation, the engine's API token and a push user, all with generated passwords |
| `woodpecker` | `ci` (needs `forge`) | `warp-local-woodpecker`, `warp-local-woodpecker-agent` (v3.20.1) | an OAuth app on the forge, the engine's sign-in (no browser), the `gitea_token` global secret; pipelines from `/build/config` |

While a component is `ready`, the forge and CI seams answer with its adapter
(`WarpEngine.forge` → `Forge::Gitea` on the internal address, `WarpEngine.ci` → the configured
`ci :woodpecker` adapter pointed at the local server), so `POST /softwares/scaffold` and the
served pipelines use them without a restart. The pipelines clone the git server's public address
through a git `insteadOf` rule and upload to `engine_url`. Starting takes a while (image pulls),
so it runs in a `WarpEngine::LocalOperation` (`WarpEngine::LocalOperationJob`) with a step log.

The Admin API (only while the components are available):

| | |
| --- | --- |
| `GET /local_components` | the components, their role, state and message |
| `POST /local_components/:key/enable` · `/disable` | `202` with an operation; enabling starts what it needs first, disabling stops what needs it |
| `DELETE /local_components/:key?purge=true` | removes the containers (with `purge` the volumes and secrets too) |
| `GET /local_components/:key/credentials` | the generated administrator sign-in (`admin:tokens`) |
| `GET /local_operations/:id` | the state, the steps and the result |
| `POST /softwares/:id/local_ci` | `202`; turns the components on, gives the software its repository, CI and CI token (`ScaffoldService#connect`), and the result names `pushUrl` (the push user's token in it) and `remoteName: "wplocal"` |
| `DELETE /softwares/:id/local_ci` | stops the CI for the software; the repository stays |

`name_prefix` (5.5, default `warp-local`) starts the container and volume names, and
`network` names the docker network the components join, so a second engine on the same machine
(the example stack: `name_prefix "warp-example"`, `network "warp-example"`) keeps its own. Without
a tool, the same work from the command line, waiting and printing the steps:

```sh
bin/rails warp_engine:local:status
bin/rails "warp_engine:local:enable[woodpecker]"      # the git server first, then the CI
bin/rails "warp_engine:local:credentials[gitea]"      # URL=, USER=, PASSWORD=
bin/rails "warp_engine:local:disable[gitea]"          # stops the CI with it
PURGE=1 bin/rails "warp_engine:local:remove[gitea]"   # containers, volumes and secrets
```

The runtime stops and removes only containers with the `org.teletypegames.warp-engine.local`
label; a container made from another spec (a newer image, changed settings) is replaced on the
next enable. A host registers its own component with `WarpEngine::Local::Components.register`.

### Other databases

The migrations are written for MySQL. On SQLite (and PostgreSQL) the MySQL-only column options
`unsigned` and `auto_increment` are accepted and left out (`WarpEngine::PortableMigrations`), so
the same migrations run there; the `charset`/`collation` table options are ignored by those
adapters anyway.

## Upgrading to 5.10

Nothing to migrate. Every generated pipeline changes in ways a repo may notice:

- a `check` step runs `make check` in the builder image where the Makefile has that
  target — a repo whose `check` target needs more than the builder image has must fix
  it or rename it;
- native targets are packed by the shared `warp_target`: each zip now has the repo's
  `LICENSE` and `README` (bevy, tic80, LÖVE and electron had none), the golang cli zips'
  root folder ends in `-cli`, and a target whose kind is neither required nor
  optional fails the build when it does not compile;
- electron's `win_x64` is optional, and its two steps are one, `binaries`;
- the c64/plus4 native players are built on every push, not only on tags; only the
  `dos` and store-engine `package` steps (`release: true`) wait for the tag;
- every step on the builder or exporter image pulls it;
- a `web_shell` that cannot be downloaded fails the build instead of packing an error
  page; bevy and ebitengine generate an `index.html` where the repo has none;
- `web.enabled: false` keeps a release off the web even when it has an `html` folder.

A template of the host's own gets `targets` and may use `warp_target`, `release: true`
and `check: false`; a platform may declare its marker `option`s. The metadata schema
wants an SPDX `license`. The Admin API's scaffold takes `app`.

## Upgrading to 5.9

A new migration adds `softwares.app` (run `bin/rails db:migrate`). The catalog envelope is
`api: 4`: an asset of a download-only kind carries `"launch": false`; a client that starts
whatever it installs should check it. The new `golang` platform needs an entry under the CI
adapter's `platforms:` with a Go builder image (cgo headers for the `gui` variant). A host CI
adapter of its own gets `built_kinds(platform, app:)` with an `app` for a platform with
variants, and a platform description has `apps`.

## Upgrading to 5.8

The `c64` and `plus4` platforms take a `.d64` as the `cartridge` beside the `.prg`
(marker option `media: d64`). Nothing changes for a PRG release. Give the C64
builder image a disk tool (`c1541`) and the exporter a `commodore-pack` that
accepts a `.d64`. A store client that filters the C64 or Plus/4 cartridge by
`ext: ".prg"` misses disk releases: set its `ext` to `""` on the *Store Engines*
page. A platform description's kinds carry `uploads` beside `upload`.

## Upgrading to 5.7

Run the new migration (the `store_clients` table). The `batocera` and
`retroarch` platforms are new: give them a builder with `python3`, `shellcheck`,
`curl` and `tar` in the host's `ci` block. The `warp_engine:store` generator is
gone: the engine serves the store engines itself under `/api/stores/<client>/`
(see *Store engines*); delete the `public/stores/batocera` and
`public/stores/retroarch` files it wrote, and set what they said on the *Store
Engines* admin page.

## Upgrading to 5.6

Run the new migration (`external_links.kind`, `ref`, the source check columns;
the fork columns of `softwares`; the `fork_links` table). It turns every kept
`Repository` link into the software's `source`. The catalog envelope is `api: 3`
(new `software` fields `source`, `forksAllowed`, `forkOf`, `forksCount`, and
`kind`, `ref`, `public` on external links). Everything else is off until you
add a `forks` block; schedule `SourceVerifyJob` and `ForkRecheckJob` (see *Forks*).

## Upgrading to 5.5.1

The local CI's git remote is `wplocal` (`remoteName` of `POST /softwares/:id/local_ci`), no longer `warp`.

## Upgrading to 5.5

Nothing to change: `local_components { name_prefix }` and the `warp_engine:local:*` tasks are new.

## Upgrading to 5.4

Run the migration (`local_components`, `local_operations`). Nothing changes until a host turns
`local_components { enable }` on; a server host leaves it off.

## Upgrading to 5.3

Run the migration (`sync_peers.allowed_channels`, `created_by`; `software_images.origin`).
Nothing else changes until you turn something on: peers keep the global channels, pairing
stays with the administrators (`inbound { pairing :anyone }` opens it), and a host whose
image adapter keeps files (`Images::HostModel`, the default) sends galleries with its
releases. `sync:pair` is a new Admin API scope; a host authenticator that maps its own
scopes may grant it.

## Upgrading to 5.2

Nothing to change: `profile`, `sync_target` and `/.well-known/warp-engine` are new, and the
migrations run on SQLite too (one data migration of 5.0 lost its MySQL-only `UPDATE … JOIN`).

## Upgrading to 5.1

Nothing to change in a host. New: the `rsync` sync transport; a peer that uses it needs
`rsync` and `ssh` in the host's image.

## Upgrading to 5.0

Sync has two directions and its partners are peers.

- Run the migrations: `sync_servers` becomes `sync_peers` (the `host` moves into
  `transport_options`, `active` becomes `outbound_enabled`), `sync_events` gets
  `sync_peer_id` (was `sync_server_id`) and `software_id` (filled in by name), `releases`
  get `origin` (`ci` for every existing one) and `sync_peer_id`.
- The initializer: the sync settings move into `outbound do … end`; naming one in the
  `sync` block raises with where it went.

  ```ruby
  sync do
    outbound do
      enabled true
      allowed_platforms %w[c64]
    end
  end
  ```

- A receiving engine now has to switch inbound on (`sync { inbound { enabled true } }`),
  and a `sync` token must belong to a peer: create a peer for each engine that pushes
  here (outbound off if you do not push back), issue its inbound token and give it to that
  engine. Older `sync` tokens owned by other records are refused (403). Releases that came
  by sync before 5.0 have `origin` `ci`; mark them `sync` if `protect_local` should not
  guard them.
- Renamed: `WarpEngine::SyncServer` → `WarpEngine::SyncPeer`, the admin *Sync Servers* →
  *Sync Peers*, Admin API `sync_servers` → `sync_peers` (`serverIds` → `peerIds`, `servers`
  → `peers`), rake `ALL_SERVERS` → `ALL_PEERS`, `Sync::Client` → `Sync::Transports::Http`,
  `Sync::ConnectionError` → `Sync::Transport::Unreachable`, `Sync.enabled?` →
  `Sync.outbound?` / `Sync.inbound?`. No aliases.
- The `warp_engine.publish` payload carries `peer`.

## Upgrading to 4.8

Nothing to change in a host. New: the Admin API reference on SysInfo, links in the
SysInfo nodes, and the `public_docs_url` setting of the `admin_api` block.

## Upgrading to 4.7

Nothing to change in a host. A manual sync run (the runner, the server page's
buttons, `POST /sync_servers/:id/push`, `POST /sync_servers/run`, `rake
warp_engine:sync:push`) now leaves out what the other server already has; send them
again with *Skip what the server already has* unticked, `skipExisting: false` or
`FORCE=1`.

## Upgrading to 4.6

Nothing to change in a host. New: the Sync Runner admin page, *Full sync* on a sync
server's page, `POST /sync_servers/run` and the run options of
`POST /sync_servers/:id/push` and `rake warp_engine:sync:push` (see *Sync*).
`SyncService#backfill` now answers a `RunResult` (`queued` is a count, `releases`
the releases).

## Upgrading to 4.5

- Run the migrations: they add the `sync_servers` and `sync_events` tables and
  `softwares.sync_enabled`. Sync stays off until the initializer turns it on (see
  *Sync*).
- New token scope `sync`. A token holding it is made `unrestricted` on save and is
  not written to any pipeline secret; in the Admin API only an unrestricted caller
  can issue one.
- The `warp_engine.publish` payload carries `source` (`:ci` or `:sync`), and
  `PublishService#publish` takes a `source:` keyword (default `:ci`).
- To prune the sync log, schedule `WarpEngine::SyncEventPruneJob`.

## Upgrading to 4.1.6

The TIC-80 pipeline's `binaries` step embeds the cart with `tic80-export` instead of
TIC-80's `export win|linux|mac`, which fetches its players from tic80.com and fails
since tic80.com serves the 1.1 players only. A host's `tic80` builder must have
`tic80-export`: `git.teletypegames.org/build/tic80pro:latest` or `:2026.11.17.3` and
later (the example stack moves to the image set `2026.11.17.3`).

## Upgrading to 4.1.5

Nothing to change in a host. The example stack moves to the image set `2026.11.17.2`: its `dos-builder` fills in a missing `dos` block from the software name, so a DOS project from the toolbox's template builds and releases.

## Upgrading to 4.1.4

Nothing to change in a host. New: `rails g warp_engine:store batocera|retroarch` writes a store config and installer for the host's catalog into `public/stores/`.

## Upgrading to 4.1.3

Nothing to change in a host. The example stack gets a catalog page at `/` (`CatalogController`, two plain views over the same data `/api/software` serves); the admin stays at `/admin`.

## Upgrading to 4.1.2

Nothing to change in a host. The example stack pins its builder images to the dated tag `2026.11.17` instead of `latest`.

## Upgrading to 4.1

- New: `WarpEngine::DevReleasePruneJob` and the `dev_release_ttl_days` and
  `dev_release_keep_branches` settings. The job is not scheduled by the engine; nothing changes
  until the host runs it.

## Upgrading to 4.0

- Migration: `releases.channel` (`stable` by default, filled from every version: `dev-…` → `dev`,
  a pre-release → `beta`); run `db:migrate`.
- `WarpEngine::Release.latest_non_dev` is gone: `WarpEngine::Release.latest(releases, channel:)`
  takes its place. A pre-release is no longer the latest release, nor offered by the outlets.
- The catalog API lists no development builds any more and gives every release its `channel`;
  `?channel=beta` lets a newer pre-release be the latest.
- New: `rake warp_engine:releases:prune_dev`, pull request preview comments (forge token with
  `write:issue`).

## Upgrading to 3.9

- `/play-preview` takes only `payload=message`; the loopback payload URL (3.7) is gone, browsers
  refuse it. The page keeps the host's `X-Frame-Options` again: nothing frames it.

## Upgrading to 3.8.2

- An EmulatorJS page starts the game at once only where the browser lets audio start without a
  click (`navigator.getAutoplayPolicy`); elsewhere (an editor's panel, a first visit) it shows
  EmulatorJS's start button, because a core whose audio cannot start draws nothing.

## Upgrading to 3.8

- The runtime page templates run as module scripts and take the payload from a `message`
  handoff in preview mode; `/play` pages behave as before.

## Upgrading to 3.7

- New, optional: `forge` (for scaffolding) and the `warp_engine.scaffold` notification.
- `GET /play-preview/...` is drawn with the catalog routes (the `wecp` outlet).

## Upgrading to 3.6

- Two migrations, both adding a column (`device_grants.scopes`, `releases.commit_sha`):
  run `db:migrate`.
- The generated publish step sends `commit=$CI_COMMIT_SHA`; an older engine ignores it.
- The admin gets a *Tool Sign In* page (not in the menu, reached through the tool's link).

## Upgrading to 3.4

- **A folder per release**: uploads land in `<name>/<version>/` and an unpacked kind
  is a folder named after the kind (`html/`, `docs/`); see [File layout](#file-layout).
  After deploying, run `bin/rails warp_engine:files:restructure DRY_RUN=1`, read the
  list, then run it without `DRY_RUN`. The old flat URLs redirect to the new ones.
- **`AssetKind#asset_name`** of an unpacked kind is the kind name (`html`), no longer
  `<name>-<version><unpack_to>`; `unpack_to` only names the old flat folder.
- **LÖVE web builds** set `<base href="/file/<name>/<version>/html/">`.
- A legacy `Updatable` service's `full_path` is in the release's folder during
  `update`.

## Upgrading to 3.3

- **C64 and Plus/4 take no `html` build**: they play in the EmulatorJS runtime. A
  publish soft-deletes a leftover `html` asset of theirs; run `runtimes:migrate` and
  `runtimes:prune_html` first if their releases still play from html folders.
- **A licence notice beside every runtime**: `runtimes:install` writes the
  runtime's `LICENSES.txt` into each installed version (an uploaded one too), and the
  player page links it (`<link rel="license">`). A runtime of your own names its
  notice with `notice`.

## Upgrading to 3.2

- **DOS plays on the web**: the `dos` platform binds to EmulatorJS with the
  `dosbox_pure` core (cross-origin isolated). Run `runtimes:install` for the core
  and `compression/extractzip.js`; new DOS releases bind on publish, the old ones
  with `runtimes:migrate UNPLAYED=1 PLATFORMS=dos` (leave out the programs that
  need a network with `EXCLUDE=`, or give them `"web": { "enabled": false }`).

## Upgrading to 3.1

- **Migrate**: `runtime_versions`, `runtime_components`, and `releases.runtime_version_id`,
  `web_binding`, `web_options`. Nothing changes for a release until a runtime is
  installed: run `bin/rails warp_engine:runtimes:install` (it downloads EmulatorJS
  4.2.3 with the cores the platforms need, about 10 MB).
- From then on new C64 and Plus/4 releases play in EmulatorJS (`playUrl` is
  `/play/...`); the old ones keep their `html` folders until `runtimes:migrate`.
- The catalog API adds `playUrl` and `players` to every release; `htmlFolderPath`
  stays. `webPlayableRelease` now counts a release that plays in a runtime.
- `metadata.json` may carry a `web` section; it goes to the release, not the software.

## Upgrading to 3.0.3

- **ActiveAdmin 4 hosts boot again.** The engine registers its admin stylesheet and
  script only where ActiveAdmin has a registry (3.x); on 4.x the host links them in
  its `_html_head` (see *Admin integration*).
- **SysInfo without CI settings.** An adapter with no URL or API token answers the
  live check as not configured instead of failing the page.

## Upgrading to 3.0.1

Nothing for a host that is already running. A new one can be installed again:
`rails g warp_engine:install` writes the base tables as
`20260805000000_create_warp_engine_tables.rb`, before the engine's own migrations, and
those add the rest. Rails 8.1 is required (the engine's migrations always were 8.1).

## Upgrading to 3.0

- **No emoji in the admin.** The menu parent is `WarpEngine` (was `🌀 WarpEngine`) and
  the items carry plain labels; a host resource that hung under the old parent moves
  with `menu parent: "WarpEngine"`. `WarpEngine::FileIcon.for` returns a
  `WarpEngine::AdminIcons` name (`:folder`, `:gamepad`, …), `FileIcon.svg` the icon.
- **The engine brings its admin assets.** `warp_engine/admin.css` and
  `warp_engine/admin.js` are registered with ActiveAdmin and precompiled; drop the
  copies of the file manager's styles (`fm-*`) and its picker script from the host.
  The picker takes the root from the server, so it no longer assumes `/softwares`.
- **Theme tokens.** The engine's pages read the host's `--c-*` custom properties
  (see *Admin integration*); the SysInfo page uses the system font stack.

## Upgrading to 2.0

The layers were made to agree with each other; a host that only uses the `shelf` and
`outlet` DSL and the public API changes nothing but its rake calls.

- **Shelves are outlets in full.** `config.shelves`, `WarpEngine::Shelves`,
  `WarpEngine::ShelfService`, `WarpEngine::ShelfPreview` and `rake warp_engine:shelves:*`
  are gone. `shelf :c64, ...` still works and stores an outlet of the type `shelf` in
  `config.outlets`, keyed by its platform (`key:` names another); a `|c|` block sets
  `c.outlets = [{ key: "c64", type: "shelf", platform: "c64", ... }]`. Use
  `rake warp_engine:outlets:{check,sync}`, `WarpEngine::Outlets::Shelf::Builder` and
  `WarpEngine::Outlets::Shelf::Preview`.
- **`GET /api/service` has no `shelves` field**: a shelf's `kinds`, `layout`, `index` and
  `urls` are in its entry under `outlets`, whose `key` is now the shelf key (`c64`), not
  its path.
- **Every outlet type has one shape** (see *Outlets*): the catalog API draws its own
  routes (`Outlets::Wecp.draw_routes`), the Assembly64 search moved to
  `Outlets::Assembly64::Catalog`, and an outlet with an unknown option fails the boot.
- **Deleting is a soft delete everywhere**: the Admin API, the admin screens (also the
  batch action) and a nested `_destroy` set `deleted_at` on a software, release, asset,
  external or platform link instead of removing the row. Creating one again under its unique key
  (a software's name, a release's version, an asset's kind) — a publish, the Admin API,
  the admin's new software — brings the deleted row back (2.0.1).
- **Outlets refresh in a job**, `WarpEngine::OutletRefreshJob`, on the host's ActiveJob
  queue, instead of inside the save or the publish request.
- **Gone aliases**: `Outlets::ConfigurationError`, `DownloadService::Denied` — rescue
  `WarpEngine::ConfigurationError` and `WarpEngine::AccessDenied`.
- **Renamed**: `AssetCoverage` is `AssetCoverageService`,
  `SoftwareHighlightedService#index` is `#show`, `FileService#show` takes `path:` (the
  `FileShowInputDto` is gone) and names a folder's index page instead of a URL,
  `Platforms::MissingAssetsError` lives beside the platform concerns, `AccessPolicy` in
  `access_policy.rb`.

## Upgrading to 1.12

Nothing a host has to change; the internals moved apart.

- **Platforms are definitions.** The built-in platform service classes
  (`WarpEngine::Platforms::<Name>::Service`) and the `Builds::*` concerns are gone;
  `Platform#publish` replaces `platform.service.update`, and `Platform#service_class` is
  no more. A host platform registers with a block (see *Platforms of your own*); the
  `service:` form still works, deprecated.
- **One CI-neutral template per platform**, `lib/warp_engine/ci/platforms/`, instead of
  one per platform and adapter; `CI::PipelineConfig::BUILT_KINDS` and `VERSION_SOURCES`
  are gone (`Platform#built_kinds`, `Platform#version_source`). The rendered pipelines
  have the same steps, images, events and artifacts; the upload step now sends every kind
  the platform accepts when it is there, and copies `metadata.json` when the build did not.
- **One error hierarchy.** Everything the engine raises on purpose is a
  `WarpEngine::Error`; `Shelves::ConfigurationError`, `Outlets::ConfigurationError` and
  `AdminApi::ConfigurationError` are all `WarpEngine::ConfigurationError`.
- **Shelves live under the shelf outlet**: `WarpEngine::Outlets::Shelf::Definitions`
  (`WarpEngine::Shelves` is its alias), with `IndexFile` and the `Layouts` beside it;
  `ShelfService` only plans and orchestrates. The unused `Shelves.refresh` is gone —
  `Outlets.refresh` does it.
- **Unpacking refuses a zip entry outside its directory** (`../`), which the upload's
  web build or docs zip could otherwise write anywhere in the file container.

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

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Teletype Games.
