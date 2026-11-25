# shellcheck shell=sh
# Defines warp_tsdoc, which writes the TypeDoc docs of a release from the
# TypeScript sources under src/. Set before it: NAME. A template calls it in
# the builder image, after npm ci:
#
#   warp_tsdoc
#
# It runs TypeDoc TYPEDOC_VERSION through npx with the repository's
# tsconfig.json, the README as the front page and the title and version on the
# pages. A typedoc.json in the repository takes over the rest of the settings.
# The site is zipped into <name>-<version>-docs.zip. Without TypeScript
# sources there are no docs, and nothing fails.
TYPEDOC_VERSION=0.28.20

warp_tsdoc() {
  if [ ! -f tsconfig.json ] || [ -z "$(find src -name '*.ts' 2>/dev/null | head -n 1)" ]; then
    echo "==> No TypeScript sources under src/: no docs"
    return 0
  fi
  W_VERSION=$(cat .version)
  W_TITLE=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1)
  [ -n "$W_TITLE" ] || W_TITLE=$NAME
  W_OUT="$(pwd)/docs"
  rm -rf "$W_OUT"
  echo "==> Generating the docs of $W_TITLE $W_VERSION with TypeDoc $TYPEDOC_VERSION"
  if [ -f typedoc.json ]; then
    npx --yes "typedoc@$TYPEDOC_VERSION" --name "$W_TITLE $W_VERSION" --out "$W_OUT"
  else
    set -- --entryPointStrategy expand --entryPoints src --exclude '**/*.test.ts' --exclude '**/*.spec.ts'
    [ -f README.md ] && set -- "$@" --readme README.md
    npx --yes "typedoc@$TYPEDOC_VERSION" "$@" --tsconfig tsconfig.json --name "$W_TITLE $W_VERSION" \
      --excludeExternals --skipErrorChecking --logLevel Warn --out "$W_OUT"
  fi
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  if command -v zip >/dev/null 2>&1; then
    (cd "$W_OUT" && zip -qr "../$W_ZIP" .)
  else
    (cd "$W_OUT" && python3 -m zipfile -c "../$W_ZIP" .)
  fi
  ls -lh "$W_ZIP"
}
