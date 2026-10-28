module WarpEngine
  # Model concern that keeps the shelves (WarpEngine::Shelves) in step with
  # the catalog: after every commit, soft delete and restore it refreshes the
  # shelves of the record's platform. The including model overrides the
  # private +shelf_platform+ to name that platform; +nil+ (the default)
  # refreshes every shelf. Does nothing when the host keeps no shelves.
  module ShelfRefreshing
    extend ActiveSupport::Concern

    included do
      after_commit :refresh_shelves
    end

    # Soft-deletes the record (see WarpEngine::SoftDeletable#soft_delete!), then
    # refreshes the shelves. Returns what the soft delete returned.
    def soft_delete!
      super.tap { refresh_shelves }
    end

    # Restores the record (see WarpEngine::SoftDeletable#restore!), then
    # refreshes the shelves. Returns what the restore returned.
    def restore!
      super.tap { refresh_shelves }
    end

    private

    def refresh_shelves
      return unless WarpEngine::Shelves.any?

      WarpEngine::Shelves.refresh(platform: shelf_platform)
    end

    def shelf_platform = nil
  end
end
