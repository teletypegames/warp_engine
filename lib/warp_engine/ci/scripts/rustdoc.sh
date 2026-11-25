# shellcheck shell=sh
# Defines warp_rustdoc, which writes the rustdoc docs of a release from the
# crate of the repository. Set before it: NAME. A template calls it in the
# builder image, where cargo is:
#
#   warp_rustdoc
#
# It runs cargo doc on the crate alone (no dependencies) with the private
# items too, since a game is a binary crate with no public API. The doc
# comments are the usual /// and //! ones. An index.html at the top leads to
# the crate's page. The site is zipped into <name>-<version>-docs.zip. Without
# a Cargo.toml there are no docs, and nothing fails.
warp_rustdoc() {
  if [ ! -f Cargo.toml ]; then
    echo "==> No Cargo.toml: no docs"
    return 0
  fi
  W_VERSION=$(cat .version)
  echo "==> Generating the docs of $NAME $W_VERSION with cargo doc"
  rm -rf target/doc
  cargo doc --no-deps --document-private-items
  W_CRATE=$(find target/doc -mindepth 2 -maxdepth 2 -name index.html | head -n 1 | sed 's|^target/doc/||')
  if [ -n "$W_CRATE" ] && [ ! -f target/doc/index.html ]; then
    printf '<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=%s"><a href="%s">%s</a>\n' \
      "$W_CRATE" "$W_CRATE" "$NAME" > target/doc/index.html
  fi
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  if command -v zip >/dev/null 2>&1; then
    (cd target/doc && zip -qr "../../$W_ZIP" .)
  else
    (cd target/doc && python3 -m zipfile -c "../../$W_ZIP" .)
  fi
  ls -lh "$W_ZIP"
}
