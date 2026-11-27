module WarpEngine
  # A title in the catalog (table +softwares+): unique +name+, +title+,
  # author, descriptions, license, +platform+ (one of
  # WarpEngine::Platform.names), +app+ (the platform variant, +cli+ or +gui+,
  # for a platform with variants; +nil+ otherwise), +status+ (a WarpEngine::SoftwareStatus key),
  # +category+ (a WarpEngine::SoftwareCategory key, registered on save),
  # +highlighted+ flag, optional +directory_name+ (its name on the platform's
  # directory), +disabled_kinds+ (the asset kinds it turns off, see
  # #disabled_kinds) and an optional polymorphic +owner+, the publisher.
  #
  # Has its gallery (+software_images+, +images+), kept +releases+ and their
  # +downloads+, kept +links+ (WarpEngine::SoftwareLink), its kept +source+
  # (WarpEngine::SoftwareSource), its +ci_repository+, the +forks+ other
  # engines announced (WarpEngine::SoftwareFork) and its +sync_events+;
  # images, links, the source and releases are editable as nested attributes. Filter scopes:
  # +with_statuses+, +with_platform+, +with_category+, +with_owner+ (each a
  # no-op for a blank value) and +search+ (title or name contains the text).
  # Soft-deletable; changes refresh the feeds (directories) of its platform.
  class Software < ApplicationRecord
    self.table_name = "softwares"

    include SoftDeletable
    include FeedRefreshing
    include RemovalNotifying

    belongs_to :owner, polymorphic: true, optional: true

    has_many :software_images, -> { ordered }, foreign_key: :software_id, dependent: :destroy
    has_many :images, through: :software_images
    has_many :releases, -> { kept }, foreign_key: :software_id
    has_many :downloads, through: :releases
    has_many :links, -> { kept }, class_name: "WarpEngine::SoftwareLink", foreign_key: :software_id, inverse_of: :software
    has_one :source, -> { kept }, class_name: "WarpEngine::SoftwareSource", foreign_key: :software_id, inverse_of: :software
    has_one :ci_repository, -> { kept }, foreign_key: :software_id
    has_many :forks, -> { kept }, class_name: "WarpEngine::SoftwareFork", foreign_key: :software_id, inverse_of: :software
    has_many :sync_events, -> { order(created_at: :desc, id: :desc) }, foreign_key: :software_id, inverse_of: :software

    accepts_nested_attributes_for :software_images, allow_destroy: true
    accepts_nested_attributes_for :links, allow_destroy: true
    accepts_nested_attributes_for :source, allow_destroy: true, reject_if: ->(attributes) { attributes["url"].blank? && attributes["id"].blank? }
    accepts_nested_attributes_for :releases, allow_destroy: true

    normalizes :category, with: ->(value) { value.to_s.strip.presence }
    normalizes :fork_of_engine, with: ->(value) { WarpEngine::Forks.normalize_url(value) }
    normalizes :fork_of_name, :fork_of_version, :fork_of_repo, with: ->(value) { value.to_s.strip.presence }
    normalizes :directory_name, with: ->(value) { value.to_s.strip.upcase.presence }
    normalizes :disabled_kinds, with: ->(value) { WarpEngine::Platform.kind_list(value).presence }

    validates :name, presence: true, uniqueness: true
    validates :title, presence: true
    validates :platform, presence: true, inclusion: { in: ->(_) { WarpEngine::Platform.names } }
    validate :app_of_platform
    validate :disabled_kinds_of_platform
    validates :status, inclusion: { in: ->(_) { WarpEngine::SoftwareStatus.keys } }, allow_blank: true
    validates :category, length: { maximum: 64 }, allow_nil: true
    validates :fork_of_name, presence: true, if: -> { fork_of_engine.present? }
    validates :directory_name, length: { maximum: 32 }, format: { with: WarpEngine::Names::PATTERN },
                           uniqueness: { scope: :platform, conditions: -> { kept } }, allow_nil: true

    after_save :register_category

    scope :with_statuses, ->(keys) { keys.blank? ? all : where(status: keys) }
    scope :with_platform, ->(name) { name.blank? ? all : where(platform: name) }
    scope :with_category, ->(key) { key.blank? ? all : where(category: key) }
    scope :with_owner, ->(owner_id) { owner_id.blank? ? all : where(owner_id: owner_id) }
    scope :search, lambda { |text|
      next all if text.blank?

      pattern = "%#{sanitize_sql_like(text.to_s.strip)}%"
      where("softwares.title LIKE :q OR softwares.name LIKE :q", q: pattern)
    }

    # Whether the developer tools may offer a fork: the author allows it and
    # the source repository is known to be readable without a sign-in.
    def forkable?
      forks_allowed? && source&.public == true
    end

    # Whether this software is a fork of another one.
    def fork? = fork_of_engine.present? && fork_of_name.present?

    # Returns the asset kinds this software turns off, a list of Strings
    # (empty by default): kinds its platform does not require, and
    # WarpEngine::Platform::WEB for the web play. Its CI pipeline neither builds
    # nor uploads them, its releases are not expected to have them and the
    # catalog leaves them out (WarpEngine::Platform#without). Set from code
    # (an Array, or a String of names separated by commas or spaces), in the
    # admin, or by the CI marker's +disable+ key on publish.
    #
    #   software.update!(disabled_kinds: %w[web win_x64 linux_x64 mac_arm64])
    def disabled_kinds = super || []

    # Returns +true+ when the asset kind +kind+ (or WarpEngine::Platform::WEB)
    # is turned off (#disabled_kinds).
    def kind_disabled?(kind) = disabled_kinds.include?(kind.to_s)

    # Returns +true+ when the web play is turned off (#disabled_kinds).
    def web_disabled? = kind_disabled?(WarpEngine::Platform::WEB)

    # Returns every status key (WarpEngine::SoftwareStatus.keys).
    def self.statuses
      WarpEngine::SoftwareStatus.keys
    end

    private

    def feed_platform
      previous = saved_changes.fetch("platform", [])[0]
      previous.present? && previous != platform ? nil : platform
    end

    def register_category
      WarpEngine::SoftwareCategory.register(category) if saved_change_to_category? && category.present?
    end

    def app_of_platform
      return unless WarpEngine::Platform.exists?(platform)

      apps = WarpEngine::Platform.find(platform).apps
      if apps.empty?
        errors.add(:app, "is not taken by the #{platform} platform") if app.present?
      elsif app.present? && !apps.include?(app)
        errors.add(:app, "must be one of #{apps.join(', ')}")
      end
    end

    def disabled_kinds_of_platform
      return if disabled_kinds.empty?

      platform = WarpEngine::Platform.find(self.platform, app: app)
      return if platform.nil?

      allowed = platform.disableable_kinds
      unknown = disabled_kinds - allowed
      errors.add(:disabled_kinds, "can only name #{allowed.join(', ')} on #{platform.label} (not #{unknown.join(', ')})") if unknown.any?
    end

    ActiveSupport.run_load_hooks(:warp_engine_software, self)
  end
end
