module WarpEngine
  # Validated input of <tt>POST /build/upload</tt>. +name+ and +version+ must
  # match NAME_FORMAT, +file+ must be an uploaded file, and its file name must
  # start with <tt><name>-<version>.</tt> or <tt><name>-<version>-</tt>.
  class UploadInputDto
    include ActiveModel::Model

    # Characters allowed in a software name and a version: letters, digits,
    # dot, underscore and hyphen.
    NAME_FORMAT = /\A[A-Za-z0-9._-]+\z/

    # The software name, the version string, the uploaded file
    # (an ActionDispatch::Http::UploadedFile) and the optional expected SHA-256
    # hex digest.
    attr_accessor :name, :version, :file, :sha256

    validates :name, format: { with: NAME_FORMAT }
    validates :version, format: { with: NAME_FORMAT }
    validate :file_present
    validate :filename_prefixed

    # Returns the base name of the uploaded file, or +nil+ when +file+ is not an
    # upload.
    def filename
      return nil unless file.respond_to?(:original_filename)

      File.basename(file.original_filename.to_s)
    end

    # Returns the validation errors joined into one sentence.
    def error_message = errors.full_messages.to_sentence

    private

    def file_present
      return if file.respond_to?(:original_filename)

      errors.add(:file, "not provided")
    end

    def filename_prefixed
      return if filename.nil? || errors.include?(:name) || errors.include?(:version)
      return if filename.start_with?("#{name}-#{version}.", "#{name}-#{version}-")

      errors.add(:file, "name must be prefixed with #{name}-#{version}")
    end
  end
end
