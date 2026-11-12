module WarpEngine
  # Model concern that keeps the materialized outlets (WarpEngine::Outlets,
  # the shelves among them) in step with the catalog: after every commit, soft
  # delete and restore it refreshes the outlets carrying the record's
  # platform. The including model overrides the private +outlet_platform+ to
  # name that platform; +nil+ (the default) refreshes every outlet. Does
  # nothing when the host configures no outlet.
  module OutletRefreshing
    extend ActiveSupport::Concern

    included do
      after_commit :refresh_outlets
    end

    # Soft-deletes the record (see WarpEngine::SoftDeletable#soft_delete!), then
    # refreshes the outlets. Returns what the soft delete returned.
    def soft_delete!
      super.tap { refresh_outlets }
    end

    # Restores the record (see WarpEngine::SoftDeletable#restore!), then
    # refreshes the outlets. Returns what the restore returned.
    def restore!
      super.tap { refresh_outlets }
    end

    private

    def refresh_outlets
      return unless WarpEngine::Outlets.any?

      WarpEngine::Outlets.refresh(platform: outlet_platform)
    end

    def outlet_platform = nil
  end
end
