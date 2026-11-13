module WarpEngine
  module CI
    # One CI-neutral pipeline step, which a CI adapter's renderer turns into its
    # own YAML (a Woodpecker step, a GitLab job).
    #
    # [name]        the step name (the GitLab stage and job name)
    # [image]       the container image
    # [commands]    the shell commands, in order
    # [environment] plain environment variables
    # [secrets]     environment variables from CI secrets: env name to secret name
    # [on]          when the step runs: +nil+ (always), +:tag+ (tag events) or
    #               +:branch+ (pushes and manual runs)
    # [artifacts]   the paths a GitLab job hands to the later stages
    # [pull]        whether Woodpecker pulls the image on every run
    # [raw]         adapter-specific keys copied verbatim (a legacy template's)
    Step = ::Data.define(:name, :image, :commands, :environment, :secrets, :on, :artifacts, :pull, :raw) do
      # Creates a step; everything but +name+ and +commands+ is optional.
      def initialize(name:, commands:, image: "alpine", environment: {}, secrets: {}, on: nil, artifacts: [], pull: false, raw: {})
        super(name: name.to_s, image: image, commands: Array(commands), environment: environment.to_h, secrets: secrets.to_h,
              on: on&.to_sym, artifacts: Array(artifacts), pull: pull ? true : false, raw: raw.to_h)
      end

      # Returns a Step built from one step of a CI-neutral template: a Hash of
      # +name+, +image+, +commands+ and optionally +environment+, +artifacts+
      # and +pull+.
      def self.from_template(hash)
        hash = hash.transform_keys(&:to_s)
        new(name: hash.fetch("name"), image: hash["image"] || "alpine", commands: hash.fetch("commands"),
            environment: hash["environment"] || {}, artifacts: hash["artifacts"] || [], pull: hash["pull"])
      end
    end

    # The shell scripts of the shared steps: <tt>lib/warp_engine/ci/scripts/*.sh</tt>
    # and each adapter's <tt>scripts/</tt>, plain sh files that shellcheck
    # lints. A step's command is the inputs as assignments followed by the
    # scripts.
    module Scripts
      # The directory of the adapter-independent scripts.
      DIR = Pathname.new(__dir__).join("scripts")

      module_function

      # Returns the script +name+ from +dir+ without its leading comment block
      # (the documentation and the shellcheck directives).
      def read(name, dir: DIR)
        Pathname.new(dir).join("#{name}.sh").read.lines.drop_while { |line| line.start_with?("#") }.join
      end

      # Returns +inputs+ as sh assignments, one a line, each value single-quoted.
      #
      #   Scripts.assign(NAME: "game") # => "NAME='game'\n"
      def assign(**inputs)
        inputs.map { |key, value| "#{key}=#{quote(value)}\n" }.join
      end

      # Returns +value+ single-quoted for sh.
      def quote(value) = "'#{value.to_s.gsub("'", %q('"'"'))}'"
    end
  end
end
