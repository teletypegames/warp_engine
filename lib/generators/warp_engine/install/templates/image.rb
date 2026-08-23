class Image < ApplicationRecord
  def self.upload_path
    ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
  end

  has_many :software_images, class_name: "WarpEngine::SoftwareImage", dependent: :restrict_with_error

  default_scope { where(deleted_at: nil) }

  attr_accessor :file_upload

  before_validation :assign_upload_attributes, if: -> { file_upload.present? }
  after_commit :store_upload_file, on: [ :create, :update ], if: -> { file_upload.present? }

  def self.ransackable_attributes(auth_object = nil)
    %w[content_type created_at deleted_at filename id original_filename updated_at]
  end

  def file_path
    File.join(self.class.upload_path, filename.to_s)
  end

  def url = "/api/image/#{id}"

  private

  def assign_upload_attributes
    self.original_filename = file_upload.original_filename
    self.content_type      = file_upload.content_type.presence || "application/octet-stream"
    self.filename          = "#{SecureRandom.uuid}#{File.extname(file_upload.original_filename)}"
  end

  def store_upload_file
    FileUtils.mkdir_p(self.class.upload_path)
    IO.copy_stream(file_upload.to_io, file_path)
  end
end
