# shellcheck shell=sh
# Defines warp_godoc, which writes the Go docs of a release. Set before it:
# NAME. A template calls it in the builder image, whose Go reads the module:
#
#   warp_godoc
#
# It runs doc2go (the image's, or go install of DOC2GO_VERSION) over every
# package of the module, with the version on the pages, and zips the site into
# <name>-<version>-docs.zip. doc2go leaves package main out, so it reads a copy
# of the sources in which package main is named after the module. Without Go
# sources there are no docs, and nothing fails.
DOC2GO_VERSION=v0.12.2

warp_godoc() {
  if [ ! -f go.mod ] || [ -z "$(find . -name '*.go' -not -path './vendor/*' | head -n 1)" ]; then
    echo "==> No Go module: no docs"
    return 0
  fi
  W_VERSION=$(cat .version)
  W_DOC2GO=$(command -v doc2go || true)
  if [ -z "$W_DOC2GO" ]; then
    echo "==> Installing doc2go $DOC2GO_VERSION"
    GOBIN=/tmp/warp-doc2go go install "go.abhg.dev/doc2go@$DOC2GO_VERSION"
    W_DOC2GO=/tmp/warp-doc2go/doc2go
  fi
  W_MODULE=$(go list -m)
  W_PKG=$(basename "$W_MODULE" | tr -c 'A-Za-z0-9_\n' '_')
  W_SRC=/tmp/warp-godoc-src
  W_OUT="$(pwd)/docs"
  rm -rf "$W_SRC" "$W_OUT"
  mkdir -p "$W_SRC"
  tar --exclude=./.git --exclude=./docs -cf - . | tar -xf - -C "$W_SRC"
  find "$W_SRC" -name '*.go' -exec sed -i -e "s/^package main\$/package $W_PKG/" -e "s/^package main_test\$/package $W_PKG""_test/" {} +
  echo "==> Generating the Go docs of $W_MODULE $W_VERSION"
  (cd "$W_SRC" && "$W_DOC2GO" -out "$W_OUT" -home "$W_MODULE" -pkg-version "$W_VERSION" -rel-link-style directory ./...)
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  if command -v zip >/dev/null 2>&1; then
    (cd "$W_OUT" && zip -qr "../$W_ZIP" .)
  else
    (cd "$W_OUT" && python3 -m zipfile -c "../$W_ZIP" .)
  fi
  rm -rf "$W_SRC"
  ls -lh "$W_ZIP"
}
