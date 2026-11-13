# shellcheck shell=sh
# Makes the GitLab release of a version tag: uploads the files
# collect_release_files (scripts/release_files.sh) lists to the project's
# generic package registry and links them, with the job token. Set before it:
# NAME, collect_release_files.
set -eu
case "$CI_COMMIT_TAG" in dev-*) echo "==> $CI_COMMIT_TAG is a dev build: no release"; exit 0 ;; esac
VERSION=$(cat .version)
collect_release_files
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"
PACKAGE="$API/packages/generic/$CI_PROJECT_NAME/$VERSION"
LINKS="[]"
for f in $FILES; do
  n=$(basename "$f")
  echo "==> Attaching $n"
  curl -fsS -H "JOB-TOKEN: $CI_JOB_TOKEN" --upload-file "$f" "$PACKAGE/$n" >/dev/null
  LINKS=$(printf '%s' "$LINKS" | jq --arg n "$n" --arg u "$PACKAGE/$n" '. + [{name: $n, url: $u, link_type: "package"}]')
done
jq -n --arg tag "$CI_COMMIT_TAG" --arg title "$TITLE $CI_COMMIT_TAG" --arg body "$NOTES" --argjson links "$LINKS" \
    '{tag_name: $tag, name: $title, description: $body, assets: {links: $links}}' |
  curl -fsS -H "JOB-TOKEN: $CI_JOB_TOKEN" -H 'Content-Type: application/json' -X POST -d @- "$API/releases" >/dev/null
