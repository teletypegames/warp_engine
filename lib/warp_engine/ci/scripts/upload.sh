# shellcheck shell=sh
# Uploads the build to the update server. Set before it: NAME, VERSION, ALWAYS
# and MAYBE (what follows <name>-<version> in the files the pipeline always
# and sometimes builds), METADATA (yes when metadata.json describes the
# software), UPDATE_SERVER and UPDATE_SECRET.
if [ -n "$METADATA" ] && [ ! -f "$NAME-$VERSION.metadata.json" ]; then
  cp metadata.json "$NAME-$VERSION.metadata.json"
fi
echo "==> Uploading artifacts for version $VERSION"
FILES=""
for suffix in $ALWAYS; do FILES="$FILES $NAME-$VERSION$suffix"; done
for suffix in $MAYBE; do
  if [ -f "$NAME-$VERSION$suffix" ]; then FILES="$FILES $NAME-$VERSION$suffix"; fi
done
for f in $FILES; do
  curl -fsS -H "X-Update-Secret: $UPDATE_SECRET" \
    -F "file=@$f" \
    "$UPDATE_SERVER/build/upload?name=$NAME&version=$VERSION" || exit 1
done
