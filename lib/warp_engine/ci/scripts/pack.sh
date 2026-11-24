# shellcheck shell=sh
# Defines warp_target, which builds and packs one native target the same way
# on every platform. Set before it: NAME. A template calls
#
#   warp_target SUFFIX MODE FUNCTION [ARGS...]
#
# SUFFIX is what follows <name>-<version> in the upload (-win-x64.zip), MODE
# is required, optional or expected (the platform's kind spec). FUNCTION
# builds the target into the fresh folder $PKG_DIR (<name>-<version> plus
# SUFFIX without .zip) and runs with errexit. The folder gets the
# repository's LICENSE and README and is zipped with one root folder (zip, or
# python3 when the image has no zip), keeping the executable bits. When
# FUNCTION fails, an optional target is left out with a warning; any other
# fails the step.
VERSION=$(cat .version)

warp_zip() {
  if command -v zip >/dev/null 2>&1; then
    zip -qry "$2" "$1"
  else
    python3 -m zipfile -c "$2" "$1"
  fi
}

warp_target() {
  W_SUFFIX="$1"
  W_MODE="$2"
  shift 2
  W_ZIP="$NAME-$VERSION$W_SUFFIX"
  PKG_DIR=$(printf '%s' "$W_ZIP" | sed 's/[.]zip$//')
  echo "==> Building $W_ZIP"
  rm -rf "$PKG_DIR" "$W_ZIP"
  mkdir -p "$PKG_DIR"
  (set -e; "$@") &
  if wait $!; then
    for W_FILE in LICENSE LICENSE.md LICENSE.txt README.md README.txt README; do
      if [ -f "$W_FILE" ] && [ ! -e "$PKG_DIR/$W_FILE" ]; then cp "$W_FILE" "$PKG_DIR/"; fi
    done
    warp_zip "$PKG_DIR" "$W_ZIP"
    rm -rf "$PKG_DIR"
    echo "==> $W_ZIP done"
    return 0
  fi
  rm -rf "$PKG_DIR"
  if [ "$W_MODE" = "optional" ]; then
    echo "WARNING: $W_ZIP does not build, left out of the release"
    return 0
  fi
  echo "ERROR: $W_ZIP is $W_MODE and does not build"
  exit 1
}
