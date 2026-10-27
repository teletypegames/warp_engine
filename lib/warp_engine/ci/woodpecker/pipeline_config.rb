require "warp_engine/ci/pipeline_config"

module WarpEngine
  module CI
    module Woodpecker
      class PipelineConfig < WarpEngine::CI::PipelineConfig
        def self.adapter = :woodpecker

        def self.templates_dir
          Pathname.new(__dir__).join("platforms")
        end

        private

        def branch_expression = "${CI_COMMIT_SOURCE_BRANCH:-${CI_COMMIT_BRANCH:-}}"

        def add_version_step(document, image:, script:)
          document["steps"] = [ { "name" => "version", "image" => image || "alpine", "commands" => [ script ] } ] +
                              Array(document["steps"])
        end

        def add_release_step(document, image:, script:)
          commands = image ? [] : [ "apk add --no-cache curl jq" ]
          document["steps"] = Array(document["steps"]) + [ {
            "name"        => "release",
            "image"       => image || "alpine",
            "environment" => { "GITEA_TOKEN" => { "from_secret" => "gitea_token" } },
            "commands"    => commands + [ script ],
            "when"        => [ { "event" => "tag" } ]
          } ]
        end

        def release_script(name)
          <<~SH + release_files_script(name) + <<~'SH'
            set -eu
            VERSION=$(cat .version)
          SH
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
          SH
        end

        def tag_only(document)
          Array(document["steps"]).each do |step|
            step["when"] = [ { "event" => "tag" } ] if RELEASE_STEPS.include?(step["name"])
          end
        end
      end
    end
  end
end
