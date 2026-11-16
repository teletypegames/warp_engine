module WarpEngine
  # One installed component of a WarpEngine::RuntimeVersion: its +kind+ (a
  # WarpEngine::Runtime::Component kind, e.g. +core+) and +key+ (e.g.
  # +vice_x64sc+). Its files are in the version's +files+.
  class RuntimeComponent < ApplicationRecord
    self.table_name = "runtime_components"

    belongs_to :runtime_version

    validates :kind, :key, presence: true
    validates :key, uniqueness: { scope: %i[runtime_version_id kind] }
  end
end
