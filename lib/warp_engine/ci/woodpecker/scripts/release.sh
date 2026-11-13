# shellcheck shell=sh
# shellcheck disable=SC2034 # the variables are read by the script that follows
# Makes the Gitea/Forgejo release of a version tag and attaches the files
# collect_release_files (scripts/release_files.sh) lists, replacing an asset of
# the same name. Set before it: NAME, collect_release_files, GITEA_TOKEN.
set -eu
case "$CI_COMMIT_TAG" in dev-*) echo "==> $CI_COMMIT_TAG is a dev build: no forge release"; exit 0 ;; esac
VERSION=$(cat .version)
collect_release_files
FORGE="$(printf '%s' "$CI_FORGE_URL" | sed 's|/*$||')/api/v1"
AUTH="Authorization: token $GITEA_TOKEN"
api() { method="$1"; path="$2"; shift 2; curl -fsS -X "$method" -H "$AUTH" "$FORGE$path" "$@"; }
RELEASE_ID=$(curl -sS -H "$AUTH" "$FORGE/repos/$CI_REPO/releases/tags/$CI_COMMIT_TAG" | jq -r '.id // empty')
if [ -z "$RELEASE_ID" ]; then
  echo "==> Creating the release $TITLE $CI_COMMIT_TAG"
  RELEASE_ID=$(jq -n --arg tag "$CI_COMMIT_TAG" --arg title "$TITLE $CI_COMMIT_TAG" --arg body "$NOTES" \
      '{tag_name: $tag, name: $title, body: $body, draft: false, prerelease: false}' |
    api POST "/repos/$CI_REPO/releases" -H 'Content-Type: application/json' -d @- | jq -r '.id // empty')
  [ -n "$RELEASE_ID" ] || { echo "ERROR: the release could not be created"; exit 1; }
fi
for f in $FILES; do
  n=$(basename "$f")
  for id in $(api GET "/repos/$CI_REPO/releases/$RELEASE_ID/assets" | jq -r --arg n "$n" '.[] | select(.name == $n) | .id'); do
    api DELETE "/repos/$CI_REPO/releases/$RELEASE_ID/assets/$id" >/dev/null
  done
  echo "==> Attaching $n"
  api POST "/repos/$CI_REPO/releases/$RELEASE_ID/assets?name=$(printf '%s' "$n" | jq -sRr @uri)" -F "attachment=@$f" >/dev/null
done
