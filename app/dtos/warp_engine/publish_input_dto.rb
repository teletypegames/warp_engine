module WarpEngine
  class PublishInputDto
    include ActiveModel::Model

    attr_accessor :platform, :name, :version

    validates :name, presence: true
    validates :version, presence: true
    validates :platform, presence: true
    validates :platform, inclusion: { in: WarpEngine::Platform::NAMES }, allow_blank: true

    def error_message = errors.full_messages.to_sentence
  end
end
