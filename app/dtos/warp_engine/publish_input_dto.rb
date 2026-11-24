module WarpEngine
  # Validated input of <tt>POST /build/publish</tt>: +name+, +version+ and
  # +platform+ are required, and +platform+ must be one of
  # WarpEngine::Platform.names; the optional +commit+ is the hex id of the
  # commit the CI built; the optional +app+ is the platform variant
  # (WarpEngine::Platform#apps; blank: the default one) and only a platform
  # with variants takes one.
  class PublishInputDto
    include ActiveModel::Model

    # The target platform name, the software name and the version string.
    attr_accessor :platform, :name, :version

    # The commit the CI built (7 to 64 hex digits), or +nil+.
    attr_accessor :commit

    # The platform variant (+cli+, +gui+), or +nil+ for the default one.
    attr_accessor :app

    validates :name, presence: true
    validates :version, presence: true
    validates :platform, presence: true
    validates :commit, format: { with: /\A[0-9a-f]{7,64}\z/ }, allow_blank: true
    validates :platform, inclusion: { in: ->(_) { WarpEngine::Platform.names } }, allow_blank: true
    validate :app_of_platform

    # Returns the validation errors joined into one sentence.
    def error_message = errors.full_messages.to_sentence

    private

    def app_of_platform
      return if app.blank? || !WarpEngine::Platform.exists?(platform)

      apps = WarpEngine::Platform.find(platform).apps
      errors.add(:app, apps.empty? ? "is not taken by the #{platform} platform" : "must be one of #{apps.join(', ')}") unless apps.include?(app.to_s)
    end
  end
end
