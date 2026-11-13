module WarpEngine
  module CI
    module Gitlab
      # Turns CI::Step objects into a GitLab CI document (one stage and job a
      # step), and a legacy GitLab template back into steps.
      class Renderer
        # The +rules+ condition of each Step#on value.
        ON = { tag: "$CI_COMMIT_TAG", branch: "$CI_COMMIT_BRANCH" }.freeze

        # Returns the document Hash of +steps+: the +stages+ in step order, one
        # job a step, then the top-level +extras+ of a legacy template.
        def render(steps, extras = {})
          jobs = steps.to_h { |step| [ step.name, render_job(step) ] }
          { "stages" => jobs.values.map { |job| job["stage"] }.uniq }.merge(jobs).merge(extras.except("stages"))
        end

        # Returns <tt>[steps, extras]</tt> of a legacy template +document+: its
        # jobs (the Hash values with a +script+) as CI::Step objects keeping
        # their other keys raw, and its other top-level keys.
        def parse(document)
          jobs = document.select { |_, job| job.is_a?(Hash) && job.key?("script") }
          steps = jobs.map do |name, job|
            Step.new(name: name, image: job["image"] || "alpine", commands: job["script"], raw: job.except("image", "script"))
          end
          [ steps, document.except("stages", *jobs.keys) ]
        end

        private

        def render_job(step)
          job = { "stage" => step.raw["stage"] || step.name, "image" => step.image }
          variables = step.environment.merge(step.secrets.transform_values { |secret| "$#{secret}" })
          job["variables"] = variables if variables.any?
          job["script"] = step.commands
          job["artifacts"] = { "paths" => step.artifacts } if step.artifacts.any?
          step.raw.each { |key, value| job[key] = value unless job.key?(key) }
          if step.on
            job.delete("only")
            job.delete("except")
            job["rules"] = [ { "if" => ON.fetch(step.on) } ]
          end
          job
        end
      end
    end
  end
end
