# shellcheck shell=sh
# Asks the update server to publish the uploaded build. Set before it: NAME,
# PLATFORM, UPDATE_SERVER and UPDATE_SECRET.
VERSION=$(cat .version)
echo "==> Publishing version $VERSION"
curl -fsS -X POST -H "X-Update-Secret: $UPDATE_SECRET" "$UPDATE_SERVER/build/publish?name=$NAME&platform=$PLATFORM&version=$VERSION"
