module WarpEngine
  module SoftDeletable
    extend ActiveSupport::Concern

    included do
      scope :kept, -> { where(deleted_at: nil) }
      scope :discarded, -> { where.not(deleted_at: nil) }
    end

    def soft_delete!
      update_column(:deleted_at, Time.current)
    end

    def restore!
      update_column(:deleted_at, nil)
    end

    def discarded?
      deleted_at.present?
    end
  end
end
