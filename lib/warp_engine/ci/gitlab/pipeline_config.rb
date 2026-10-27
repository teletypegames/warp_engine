require "warp_engine/ci/pipeline_config"

module WarpEngine
  module CI
    module Gitlab
      class PipelineConfig < WarpEngine::CI::PipelineConfig
        def self.adapter = :gitlab

        def self.templates_dir
          Pathname.new(__dir__).join("platforms")
        end

        private

        def branch_expression = "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-${CI_COMMIT_BRANCH:-}}"

        def add_version_step(document, image:, script:)
          job = { "stage" => "version", "image" => image || "alpine", "script" => [ script ],
                  "artifacts" => { "paths" => [ ".version" ] } }
          stages = [ "version" ] + (Array(document["stages"]) - [ "version" ])
          rest = document.except("stages", "version")
          document.replace({ "stages" => stages, "version" => job }.merge(rest))
        end

        def add_release_step(document, image:, script:)
          document["stages"] = Array(document["stages"]) - [ "release" ] + [ "release" ]
          document["release"] = {
            "stage"  => "release",
            "image"  => image || "alpine",
            "rules"  => [ { "if" => "$CI_COMMIT_TAG" } ],
            "script" => (image ? [] : [ "apk add --no-cache curl jq" ]) + [ script ]
          }
        end

        def release_script(name)
          <<~SH + release_files_script(name) + <<~'SH'
            set -eu
            VERSION=$(cat .version)
          SH
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
          SH
        end

        def tag_only(document)
          RELEASE_STEPS.each do |job|
            next unless document[job].is_a?(Hash)

            document[job].delete("only")
            document[job].delete("except")
            document[job]["rules"] = [ { "if" => "$CI_COMMIT_TAG" } ]
          end
        end
      end
    end
  end
end
