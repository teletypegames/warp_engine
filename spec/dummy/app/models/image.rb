class Image < ActiveRecord::Base
  def self.upload_path
    Rails.root.join("tmp/images").to_s
  end

  has_many :software_images, class_name: "WarpEngine::SoftwareImage", dependent: :restrict_with_error

  default_scope { where(deleted_at: nil) }

  attr_accessor :file_upload

  before_save :process_upload, if: -> { file_upload.present? }

  def file_path
    File.join(self.class.upload_path, filename.to_s)
  end

  private

  def process_upload
    FileUtils.mkdir_p(self.class.upload_path)
    self.original_filename = file_upload.original_filename
    self.content_type      = file_upload.content_type.presence || "application/octet-stream"
    self.filename          = "#{SecureRandom.uuid}#{File.extname(file_upload.original_filename)}"
    IO.copy_stream(file_upload.to_io, file_path)
  end
end
