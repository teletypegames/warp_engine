module WarpEngine
  class Image < ApplicationRecord
    def self.upload_path
      WarpEngine.config.image_container_path
    end

    has_many :software_images, dependent: :restrict_with_error

    default_scope { where(deleted_at: nil) }

    attr_accessor :file_upload

    before_save :process_upload, if: -> { file_upload.present? }

    def self.ransackable_attributes(auth_object = nil)
      %w[content_type created_at deleted_at filename id original_filename updated_at]
    end

    def file_path
      File.join(self.class.upload_path, filename.to_s)
    end

    ActiveSupport.run_load_hooks(:warp_engine_image, self)

    private

    def process_upload
      FileUtils.mkdir_p(self.class.upload_path)
      self.original_filename = file_upload.original_filename
      self.content_type      = file_upload.content_type.presence || "application/octet-stream"
      ext                    = File.extname(file_upload.original_filename)
      self.filename          = "#{SecureRandom.uuid}#{ext}"
      IO.copy_stream(file_upload.to_io, file_path)
    end
  end
end
