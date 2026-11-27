module WarpEngine
  # A long task on the local providers (table +local_tasks+), run by
  # WarpEngine::LocalTaskJob: its +kind+ (one of KINDS), its +target+ (a
  # provider key or a software id), its +state+ (one of STATES), the +steps+
  # it went through (a list of <tt>{ "at", "text" }</tt>), its +result+ and
  # the +error+ it stopped at.
  class LocalTask < ApplicationRecord
    self.table_name = "local_tasks"

    # What a task does.
    KINDS = %w[enable disable remove purge local_ci].freeze

    # The states, in the order a task passes them.
    STATES = %w[queued running succeeded failed].freeze

    validates :kind, inclusion: { in: KINDS }
    validates :state, inclusion: { in: STATES }
    validates :target, presence: true

    # Logs the step +text+ and returns it.
    def step!(text)
      update!(steps: Array(steps) + [ { "at" => Time.current.iso8601, "text" => text.to_s } ])
      text
    end

    # Returns +true+ once it succeeded or failed.
    def finished? = %w[succeeded failed].include?(state)
  end
end
