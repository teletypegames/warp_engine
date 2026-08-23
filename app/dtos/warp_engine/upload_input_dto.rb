module WarpEngine
  class UploadInputDto
    include ActiveModel::Model

    NAME_FORMAT = /\A[A-Za-z0-9._-]+\z/

    attr_accessor :name, :version, :file, :sha256

    validates :name, format: { with: NAME_FORMAT }
    validates :version, format: { with: NAME_FORMAT }
    validate :file_present
    validate :filename_prefixed

    def filename
      return nil unless file.respond_to?(:original_filename)

      File.basename(file.original_filename.to_s)
    end

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
