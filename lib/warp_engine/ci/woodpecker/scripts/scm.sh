# shellcheck shell=sh
# The Gitea/Forgejo tag API for scripts/tag.sh, with the GITEA_TOKEN secret.
SCM="$(printf '%s' "$CI_FORGE_URL" | sed 's|/*$||')/api/v1/repos/$CI_REPO"
AUTH="Authorization: token $GITEA_TOKEN"
scm_tag_lookup() {
  curl -sS -H "$AUTH" "$SCM/tags/$TAG" | sed -n 's/.*"commit":{[^}]*"sha":"\([0-9a-f]*\)".*/\1/p'
}
scm_tag_delete() {
  curl -fsS -X DELETE -H "$AUTH" "$SCM/tags/$TAG"
}
scm_tag_create() {
  printf '{"tag_name":"%s","target":"%s"}' "$TAG" "$CI_COMMIT_SHA" |
    curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -d @- "$SCM/tags"
}
