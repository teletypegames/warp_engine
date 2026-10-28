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

## Releases

See the release flow in the repo's `.woodpecker/warp_engine.yaml`: bump
`lib/warp_engine/version.rb`, then tag `warp_engine-vX.Y.Z`. The tag publishes
the gem and the RDoc.
