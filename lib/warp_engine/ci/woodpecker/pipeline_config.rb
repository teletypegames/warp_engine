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

        def tag_only(document)
          Array(document["steps"]).each do |step|
            step["when"] = [ { "event" => "tag" } ] if RELEASE_STEPS.include?(step["name"])
          end
        end
      end
    end
  end
end
