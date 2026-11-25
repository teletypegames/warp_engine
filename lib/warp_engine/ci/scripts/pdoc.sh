# shellcheck shell=sh
# Defines warp_pdoc, which writes the pdoc docs of a release from the Python
# modules under a folder. Set before it: NAME. A template calls it with the
# folder, in an image with Python and pip:
#
#   warp_pdoc dist
#
# It installs pdoc PDOC_VERSION with pip and documents every *.py under the
# folder (the modules a module imports from beside it are found), with their
# docstrings and the title and version on the pages. The site is zipped into
# <name>-<version>-docs.zip. Without Python modules there are no docs, and
# nothing fails.
PDOC_VERSION=15.0.4

warp_pdoc() {
  W_FILES=$(find "$1" -type f -name '*.py' -not -name 'test_*' -not -path '*/__pycache__/*' 2>/dev/null | sort)
  if [ -z "$W_FILES" ]; then
    echo "==> No Python modules under $1/: no docs"
    return 0
  fi
  W_VERSION=$(cat .version)
  W_TITLE=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1)
  [ -n "$W_TITLE" ] || W_TITLE=$NAME
  W_OUT="$(pwd)/docs"
  rm -rf "$W_OUT"
  echo "==> Generating the docs of $W_TITLE $W_VERSION with pdoc $PDOC_VERSION"
  python3 -m pip install --quiet --disable-pip-version-check --root-user-action=ignore "pdoc==$PDOC_VERSION"
  # shellcheck disable=SC2086
  python3 -m pdoc --footer-text "$W_TITLE $W_VERSION" -o "$W_OUT" $W_FILES
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  (cd "$W_OUT" && python3 -m zipfile -c "../$W_ZIP" .)
  ls -lh "$W_ZIP"
}
