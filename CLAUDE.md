# CLAUDE.md

WarpEngine: the mountable Rails engine behind the teletypegames catalog.
`README.md` is the user guide; the API reference is the RDoc published to the
wiki at https://wiki.teletypegames.org/rdoc/warp_engine/latest/ on every
`warp_engine-vX.Y.Z` tag.

## Documenting code: write for RDoc

The rest of the teletypegames repo keeps no explanatory comments, and that
still holds inside method bodies here. The exception is the RDoc comment: the
API reference is generated from `app/` and `lib/`, and CI fails below 100%
coverage. Every change keeps the engine fully documented:

- Every class, module, constant, attribute (`attr_*`) and public or protected
  method gets an RDoc comment directly above it. Private methods are not
  required, but document them when the behaviour is not obvious.
- Say what the thing is or does, its arguments, its return value, the
  exceptions it raises and side effects (records written, jobs enqueued, HTTP
  status rendered). For controller actions name the route and the response.
  Not its history: the why of a change goes in the commit.
- Use RDoc markup, not Markdown or YARD tags: `+code+` for a single word,
  `<tt>code with spaces</tt>`, `*bold*`, `_emphasis_`, cross-references by
  name (`WarpEngine::Software`, `#call`), labelled lists for options:

    # Upserts the release of +software+ from the CI upload.
    #
    # [software] the WarpEngine::Software being released
    # [version]  the version string from metadata.json
    #
    # Returns the saved WarpEngine::Release. Raises
    # WarpEngine::UpdaterError when the upload has no metadata.

- Examples go in an indented block (two extra spaces after the `#`).
- One comment above an `attr_reader :a, :b` line documents all names on it;
  give each constant its own comment.
- Do not hide things from RDoc with `:nodoc:` to reach the coverage; make a
  helper `private` instead if it is not part of the API.
- Check before committing (rubocop must stay clean too):

    rdoc -C -x templates app lib     # must print 100.00% documented

## Typed seams: RBS

Only the adapter contracts are typed (`sig/`, see *Typed adapter contracts* in
the README): the interfaces a host implements, the base classes it subclasses
and the value objects they pass. Do not type the rest of the engine.

- A change to a seam method's parameters or return changes its signature in
  `sig/` in the same commit; a new seam gets its interface there and its file
  in the `Steepfile`.
- `steep/stubs` stands in for Rails and the untyped engine; it is not shipped.
- Where Steep cannot follow the code (`Struct.new`/`Data.define` blocks,
  narrowing by `respond_to?`), a `# steep:ignore` directive, never a cast in
  the code. Prefer code Steep can follow (`case` over a predicate helper).
- Check before committing:

    bundle exec rbs -I sig -I steep/stubs validate && bundle exec steep check

## Layers

Keep new code in the layer its neighbours are in; 2.0 made them agree.

- **Models** (`app/models`) hold data rules only. They do not reach up into
  services or feeds; what both need (e.g. the name rules of
  `WarpEngine::Names`) lives in a neutral module in `lib/warp_engine`.
  Soft-deletable records are only ever soft-deleted (`soft_delete!`, a nested
  `_destroy` included), never destroyed.
- **Services** (`app/services`) are named `*Service`, except the parts of one
  (`Publish::*`) and the catalog's selection (`Catalog::Selection`). They take keyword
  arguments, return data or result objects, raise their own errors (beside
  them, not in `errors.rb`), and know no routes or URLs.
- **Controllers** stay thin: parse the request, call one service, render. They
  share request parsing through concerns (`CatalogFilters`), the version header
  through `VersionHeader`, and use nested `module ... class` declarations.
- **Admin layers** (ActiveAdmin and the Admin API) are CRUD over the models;
  anything more than a save goes through a service. The admin pages bring
  their own styles and scripts (`app/assets/*/warp_engine/admin.*`), use no
  emoji (`WarpEngine::AdminIcons` instead), no hardcoded colors (the host's
  `--c-*` tokens via `var(--we-*)`), and no host paths.
- **Feeds**: one shape for every type — `lib/warp_engine/feeds/TYPE.rb`
  (options, `validate!`, `descriptor`, `draw_routes` or `sync!`) plus the
  objects that do the work in `lib/warp_engine/feeds/TYPE/`, taking the
  feed. The catalog API (`Wecp`) draws its own routes too; only the build
  and CI endpoints stay in `config/routes.rb`.
- No compatibility aliases for renamed constants: rename, note it under
  *Upgrading* in the README, and bump the major version.

## Releases

See the release flow in the repo's `.woodpecker/warp_engine.yaml`: bump
`lib/warp_engine/version.rb`, then tag `warp_engine-vX.Y.Z`. The tag publishes
the gem and the RDoc.
