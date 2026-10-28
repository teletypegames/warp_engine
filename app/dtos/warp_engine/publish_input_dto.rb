module WarpEngine
  # Validated input of <tt>POST /build/publish</tt>: +name+, +version+ and
  # +platform+ are required, and +platform+ must be one of
  # WarpEngine::Platform.names.
  class PublishInputDto
    include ActiveModel::Model

    # The target platform name, the software name and the version string.
    attr_accessor :platform, :name, :version

    validates :name, presence: true
    validates :version, presence: true
    validates :platform, presence: true
    validates :platform, inclusion: { in: ->(_) { WarpEngine::Platform.names } }, allow_blank: true

    # Returns the validation errors joined into one sentence.
    def error_message = errors.full_messages.to_sentence
  end
end
