# shellcheck shell=sh
# The GitLab tag API for scripts/tag.sh, with the TAG_TOKEN project variable.
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID/repository/tags"
AUTH="PRIVATE-TOKEN: $TAG_TOKEN"
forge_tag_lookup() {
  curl -sS -H "$AUTH" "$API/$TAG" | sed -n 's/.*"commit":{[^}]*"id":"\([0-9a-f]*\)".*/\1/p'
}
forge_tag_delete() {
  curl -fsS -X DELETE -H "$AUTH" "$API/$TAG"
}
forge_tag_create() {
  curl -fsS -X POST -H "$AUTH" --data-urlencode "tag_name=$TAG" --data-urlencode "ref=$CI_COMMIT_SHA" "$API"
}
