module WarpEngine
  module CI
    module Woodpecker
      # Turns CI::Step objects into a Woodpecker pipeline document, and a legacy
      # Woodpecker template back into steps.
      class Renderer
        # The events a generated pipeline starts on: every one but +release+.
        EVENTS = %w[push pull_request pull_request_closed pull_request_metadata tag deployment cron manual].freeze
        # The +when+ event of each Step#on value.
        ON = { tag: "tag", branch: %w[push manual] }.freeze

        # Returns the pipeline Hash of +steps+, with the document-level +extras+
        # of a legacy template; the pipeline starts on EVENTS unless +extras+
        # filter it already.
        def render(steps, extras = {})
          document = { "steps" => steps.map { |step| render_step(step) } }.merge(extras)
          document["when"] ||= [ { "event" => EVENTS } ]
          document
        end

        # Returns <tt>[steps, extras]</tt> of a legacy template +document+: its
        # steps as CI::Step objects keeping their other keys raw, and its other
        # top-level keys.
        def parse(document)
          steps = Array(document["steps"]).map do |step|
            Step.new(name: step["name"], image: step["image"] || "alpine", commands: step["commands"] || [],
                     raw: step.except("name", "image", "commands"))
          end
          [ steps, document.except("steps") ]
        end

        private

        def render_step(step)
          rendered = { "name" => step.name, "image" => step.image }
          rendered["pull"] = true if step.pull
          environment = step.environment.merge(step.secrets.transform_values { |secret| { "from_secret" => secret } })
          rendered["environment"] = environment if environment.any?
          rendered["commands"] = step.commands
          step.raw.each { |key, value| rendered[key] = value unless rendered.key?(key) }
          rendered["when"] = [ { "event" => ON.fetch(step.on) } ] if step.on
          rendered
        end
      end
    end
  end
end
