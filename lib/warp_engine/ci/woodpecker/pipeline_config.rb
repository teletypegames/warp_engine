require "warp_engine/ci/pipeline_config"
require "warp_engine/ci/woodpecker/renderer"

module WarpEngine
  module CI
    module Woodpecker
      # The Woodpecker pipeline of a platform: CI::PipelineConfig rendered by
      # Woodpecker::Renderer, with the Gitea/Forgejo forge scripts
      # (<tt>woodpecker/scripts/</tt>) and the +gitea_token+ secret for the tag
      # and release steps.
      class PipelineConfig < WarpEngine::CI::PipelineConfig
        # The events a generated pipeline starts on (Renderer::EVENTS).
        EVENTS = Renderer::EVENTS

        # Returns +:woodpecker+.
        def self.adapter = :woodpecker

        private

        def renderer = Renderer.new

        def scripts_dir = Pathname.new(__dir__).join("scripts")

        def branch_expression = "${CI_COMMIT_SOURCE_BRANCH:-${CI_COMMIT_BRANCH:-}}"

        def default_branch_expression = "${CI_REPO_DEFAULT_BRANCH:-}"

        def forge_secrets = { "GITEA_TOKEN" => "gitea_token" }
      end
    end
  end
end
