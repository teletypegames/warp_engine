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
