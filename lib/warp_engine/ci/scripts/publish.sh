# shellcheck shell=sh
# Asks the update server to publish the uploaded build. Set before it: NAME,
# PLATFORM, UPDATE_SERVER and UPDATE_SECRET; CI_COMMIT_SHA, when the CI sets
# it, is sent as the release's commit, and APP, when set, as the platform
# variant.
VERSION=$(cat .version)
echo "==> Publishing version $VERSION"
APP_QUERY=""
if [ -n "$APP" ]; then APP_QUERY="&app=$APP"; fi
curl -fsS -X POST -H "X-Update-Secret: $UPDATE_SECRET" "$UPDATE_SERVER/build/publish?name=$NAME&platform=$PLATFORM&version=$VERSION&commit=$CI_COMMIT_SHA$APP_QUERY"
