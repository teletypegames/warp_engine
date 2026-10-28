require "warp_engine/ci/pipeline_config"

module WarpEngine
  module CI
    module Woodpecker
      # The CI::PipelineConfig of Woodpecker: renders the templates under
      # +platforms/+ next to this file and adds the shared steps as Woodpecker
      # +steps+, tagging and releasing through the Gitea/Forgejo API with the
      # +gitea_token+ secret.
      class PipelineConfig < WarpEngine::CI::PipelineConfig
        # The events a generated pipeline runs on when its template sets no +when+:
        # every Woodpecker event but +release+, which moving a dev tag also sends
        # and which would build the tag a second time.
        EVENTS = %w[push pull_request pull_request_closed pull_request_metadata tag deployment cron manual].freeze

        # Returns +:woodpecker+, the key of Woodpecker templates in a platform registration.
        def self.adapter = :woodpecker

        # Returns the Pathname of the bundled Woodpecker templates.
        def self.templates_dir
          Pathname.new(__dir__).join("platforms")
        end

        private

        def branch_expression = "${CI_COMMIT_SOURCE_BRANCH:-${CI_COMMIT_BRANCH:-}}"

        def default_branch_expression = "${CI_REPO_DEFAULT_BRANCH:-}"

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

        def limit_events(document)
          document["when"] ||= [ { "event" => EVENTS } ]
        end

        def add_tag_step(document, image:, script:)
          commands = image ? [] : [ "apk add --no-cache curl" ]
          document["steps"] = Array(document["steps"]) + [ {
            "name"        => "tag",
            "image"       => image || "alpine",
            "environment" => { "GITEA_TOKEN" => { "from_secret" => "gitea_token" } },
            "commands"    => commands + [ script ],
            "when"        => [ { "event" => %w[push manual] } ]
          } ]
        end

        def forge_tag_setup
          <<~'SH'
            FORGE="$(printf '%s' "$CI_FORGE_URL" | sed 's|/*$||')/api/v1/repos/$CI_REPO"
            AUTH="Authorization: token $GITEA_TOKEN"
          SH
        end

        def forge_tag_lookup
          <<~'SH'.chomp
            curl -sS -H "$AUTH" "$FORGE/tags/$TAG" | sed -n 's/.*"commit":{[^}]*"sha":"\([0-9a-f]*\)".*/\1/p'
          SH
        end

        def forge_tag_delete = %(curl -fsS -X DELETE -H "$AUTH" "$FORGE/tags/$TAG")

        def forge_tag_create
          %(printf '{"tag_name":"%s","target":"%s"}' "$TAG" "$CI_COMMIT_SHA" | ) +
            %(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -d @- "$FORGE/tags")
        end

        def release_script(name)
          <<~SH + release_files_script(name) + <<~'SH'
            set -eu
            case "$CI_COMMIT_TAG" in dev-*) echo "==> $CI_COMMIT_TAG is a dev build: no forge release"; exit 0 ;; esac
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
