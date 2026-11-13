# shellcheck shell=sh
# Tags the commit on the forge after a push: v<version> once, or the moving
# dev-<branch> tag of a dev build. Set before it: BRANCH_SOURCE, and the
# forge_tag_lookup, forge_tag_delete and forge_tag_create functions of the
# CI adapter (TAG and CI_COMMIT_SHA are theirs to read).
set -eu
VERSION=$(cat .version)
BRANCH=$(printf '%s' "$BRANCH_SOURCE" | tr '/' '-')
case "$VERSION" in
  dev-*) TAG="dev-$BRANCH"; MOVE=yes ;;
  *) TAG="v$VERSION"; MOVE="" ;;
esac
if [ "$TAG" = "dev-" ]; then echo "No branch to name the dev tag after: nothing to tag"; exit 0; fi
CURRENT=$(forge_tag_lookup 2>/dev/null || true)
if [ -n "$CURRENT" ]; then
  if [ -z "$MOVE" ]; then echo "==> $TAG is tagged already: this build releases nothing"; exit 0; fi
  if [ "$CURRENT" = "$CI_COMMIT_SHA" ]; then echo "==> $TAG is on this commit already"; exit 0; fi
  echo "==> Moving $TAG to $CI_COMMIT_SHA"
  forge_tag_delete >/dev/null
else
  echo "==> Tagging $CI_COMMIT_SHA as $TAG"
fi
forge_tag_create >/dev/null
