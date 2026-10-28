module WarpEngine
  # Model concern for soft deletion through a +deleted_at+ column. Adds the
  # scopes +kept+ (not deleted) and +discarded+ (deleted).
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

    # Returns whether the record is soft-deleted.
    def discarded?
      deleted_at.present?
    end
  end
end
