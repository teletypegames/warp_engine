# shellcheck shell=sh
# Asks the update server to publish the uploaded build. Set before it: NAME,
# PLATFORM, UPDATE_SERVER and UPDATE_SECRET; CI_COMMIT_SHA, when the CI sets
# it, is sent as the release's commit, APP, when set, as the platform
# variant, and DISABLE, when set, as the kinds the software turns off.
VERSION=$(cat .version)
echo "==> Publishing version $VERSION"
APP_QUERY=""
if [ -n "$APP" ]; then APP_QUERY="&app=$APP"; fi
DISABLE_QUERY=""
if [ -n "$DISABLE" ]; then DISABLE_QUERY="&disable=$DISABLE"; fi
curl -fsS -X POST -H "X-Update-Secret: $UPDATE_SECRET" "$UPDATE_SERVER/build/publish?name=$NAME&platform=$PLATFORM&version=$VERSION&commit=$CI_COMMIT_SHA$APP_QUERY$DISABLE_QUERY"
