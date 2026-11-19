require "digest"

module WarpEngine
  # An image in a software's gallery: links the software to an image record
  # of the host's image model (WarpEngine::Images.model_name), with a
  # +position+ (scope +ordered+) and an +is_default+ flag; setting it clears
  # the flag on the software's other images. An image may be given as an
  # upload in #file_upload, which is stored on validation. Its +origin+ says
  # who set it: +local+ (the admin, the Admin API, the CI) or +sync+ (another
  # engine, WarpEngine::SyncImagesService).
  #
  # Every change is published as the <tt>warp_engine.software_images</tt>
  # notification (NOTIFICATION) with the +software_id+ and the +origin+, so
  # outbound sync can send the images on (WarpEngine::SyncService#dispatch_images).
  class SoftwareImage < ApplicationRecord
    # The values of +origin+.
    ORIGINS = %w[local sync].freeze

    # The notification published after every change.
    NOTIFICATION = "warp_engine.software_images".freeze

    belongs_to :software
    belongs_to :image, optional: true, class_name: WarpEngine::Images.model_name

    # An uploaded file to create the image record from on validation.
    attr_accessor :file_upload

    before_validation :create_image_from_upload, if: -> { file_upload.present? }

    validates :image_id, presence: true
    validates :image_id, uniqueness: { scope: :software_id }
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :origin, inclusion: { in: ORIGINS }

    before_save :unset_other_defaults, if: -> { is_default? && is_default_changed? }

    scope :ordered, -> { order(:position) }

    after_commit :announce

    # Returns +true+ when another engine set the image by sync.
    def synced? = origin == "sync"

    # Returns the SHA-256 hex digest of the image's file, or +nil+ when the
    # image adapter keeps no file of it (WarpEngine::Images.file_path_for).
    def sha256
      path = WarpEngine::Images.file_path_for(image_id)
      path && Digest::SHA256.file(path).hexdigest
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

    def announce
      ActiveSupport::Notifications.instrument(NOTIFICATION, software_id: software_id, origin: origin)
    end

    def unset_other_defaults
      SoftwareImage.where(software_id: software_id, is_default: true)
                   .where.not(id: id)
                   .update_all(is_default: false)
    end
  end
end
