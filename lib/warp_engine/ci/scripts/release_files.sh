# shellcheck shell=sh
# shellcheck disable=SC2034 # the variables are read by the script that follows
# Defines collect_release_files, which sets FILES (what to attach to the forge
# release: the build's own .release-assets list, or the versioned files),
# TITLE and NOTES (RELEASE_NOTES.md). Set before it is called: NAME, VERSION.
collect_release_files() {
  if [ -f .release-assets ]; then
    FILES=$(cat .release-assets)
  else
    FILES=$(find . -maxdepth 1 -type f \( -name "$NAME-$VERSION.*" -o -name "$NAME-$VERSION-*" \) ! -name '*.metadata.json' | sed 's|^\./||' | sort)
  fi
  [ -n "$FILES" ] || { echo "ERROR: nothing to attach to the release"; exit 1; }
  TITLE=$(jq -r '.title // .name // empty' metadata.json 2>/dev/null || true)
  if [ -z "$TITLE" ]; then TITLE="$NAME"; fi
  NOTES=""
  if [ -f RELEASE_NOTES.md ]; then NOTES=$(cat RELEASE_NOTES.md); fi
}
