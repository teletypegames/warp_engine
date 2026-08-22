module WarpEngine
  class SoftwareImage < ApplicationRecord
    belongs_to :software
    belongs_to :image, optional: true, class_name: WarpEngine::Images.model_name

    attr_accessor :file_upload

    before_validation :create_image_from_upload, if: -> { file_upload.present? }

    validates :image_id, presence: true
    validates :image_id, uniqueness: { scope: :software_id }
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    before_save :unset_other_defaults, if: -> { is_default? && is_default_changed? }

    default_scope { order(:position) }

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at id image_id is_default position software_id updated_at]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[image software]
    end

    ActiveSupport.run_load_hooks(:warp_engine_software_image, self)

    private

    def create_image_from_upload
      img = WarpEngine::Images.build_from_upload(file_upload)
      if img.save
        self.image = img
      else
        errors.add(:file_upload, img.errors.full_messages.join(", "))
      end
    end

    def unset_other_defaults
      SoftwareImage.where(software_id: software_id, is_default: true)
                   .where.not(id: id)
                   .update_all(is_default: false)
    end
  end
end
