require "warp_engine/ci/pipeline_config"
require "warp_engine/ci/gitlab/renderer"

module WarpEngine
  module CI
    module Gitlab
      # The GitLab pipeline of a platform: CI::PipelineConfig rendered by
      # Gitlab::Renderer, with the GitLab forge scripts (<tt>gitlab/scripts/</tt>:
      # tags with the +TAG_TOKEN+ project variable, releases with the job token).
      class PipelineConfig < WarpEngine::CI::PipelineConfig
        # Returns +:gitlab+.
        def self.adapter = :gitlab

        private

        def renderer = Renderer.new

        def scripts_dir = Pathname.new(__dir__).join("scripts")

        def branch_expression = "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-${CI_COMMIT_BRANCH:-}}"

        def default_branch_expression = "${CI_DEFAULT_BRANCH:-}"
      end
    end
  end
end
