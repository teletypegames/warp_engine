module WarpEngine
  # Model concern for soft deletion through a +deleted_at+ column. Adds the
  # scopes +kept+ (not deleted) and +discarded+ (deleted).
  #
  # Deleting such a record anywhere in the engine (the Admin API, the admin
  # screens, a nested <tt>_destroy</tt>, a publish that drops an asset) is a
  # soft delete; only the records without the column are destroyed.
  module SoftDeletable
    extend ActiveSupport::Concern

    included do
      scope :kept, -> { where(deleted_at: nil) }
      scope :discarded, -> { where.not(deleted_at: nil) }
    end

    # Marks the record deleted by setting +deleted_at+ to now, without
    # validations or callbacks.
    def soft_delete!
      update_column(:deleted_at, Time.current)
    end

    # Clears +deleted_at+, without validations or callbacks.
    def restore!
      update_column(:deleted_at, nil)
    end

    # Takes the place of the nested-attributes destroy mark: a
    # <tt>_destroy</tt> entry soft-deletes the record when its parent is
    # saved, instead of destroying it.
    def mark_for_destruction
      self.deleted_at = Time.current
    end

    # Returns whether the record is soft-deleted.
    def discarded?
      deleted_at.present?
    end
  end
end
