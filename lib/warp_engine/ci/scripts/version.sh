# shellcheck shell=sh
# Writes the build's version to .version. Set before it: SOURCE_VERSION (what
# the source names), BRANCH_SOURCE and DEFAULT_BRANCH_SOURCE (the CI's branch
# and default branch). A version tag must match the source; a build off the
# default branch, or of a dev-<branch> tag, is dev-<version>-<branch>.
TAG="${CI_COMMIT_TAG:-}"
TAG_VERSION=""
DEV_TAG=""
BRANCH=$(printf '%s' "$BRANCH_SOURCE" | tr '/' '-')
case "$TAG" in
  v[0-9]*|[0-9]*) TAG_VERSION=$(printf '%s' "$TAG" | sed 's/^v//') ;;
  dev-*) DEV_TAG=yes; BRANCH=$(printf '%s' "$TAG" | sed 's/^dev-//') ;;
esac
if [ -n "$TAG_VERSION" ] && [ -n "$SOURCE_VERSION" ] && [ "$TAG_VERSION" != "$SOURCE_VERSION" ]; then
  echo "ERROR: the tag $TAG does not match the version $SOURCE_VERSION of the source!"
  exit 1
fi
VERSION="$SOURCE_VERSION"
if [ -z "$VERSION" ]; then VERSION="$TAG_VERSION"; fi
if [ -z "$VERSION" ]; then
  SHA="${CI_COMMIT_SHA:-unknown}"
  VERSION="dev-$(printf '%.7s' "$SHA")"
  echo "No version in the source and no version tag: this build is $VERSION"
fi
DEFAULT_BRANCH=$(printf '%s' "$DEFAULT_BRANCH_SOURCE" | tr '/' '-')
ON_DEFAULT=""
if [ -n "$DEFAULT_BRANCH" ]; then
  if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then ON_DEFAULT=yes; fi
else
  case "$BRANCH" in main|master) ON_DEFAULT=yes ;; esac
fi
if [ -n "$DEV_TAG" ] || { [ -z "$TAG" ] && [ -n "$BRANCH" ] && [ -z "$ON_DEFAULT" ]; }; then
  case "$VERSION" in dev-*) ;; *) VERSION="dev-$VERSION-$BRANCH" ;; esac
fi
echo "VERSION is: $VERSION"
echo "$VERSION" > .version
