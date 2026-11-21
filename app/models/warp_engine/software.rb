module WarpEngine
  # A title in the catalog (table +softwares+): unique +name+, +title+,
  # author, descriptions, license, +platform+ (one of
  # WarpEngine::Platform.names), +status+ (a WarpEngine::SoftwareStatus key),
  # +category+ (a WarpEngine::SoftwareCategory key, registered on save),
  # +highlighted+ flag, optional +shelf_name+ (its name on the platform's
  # shelf) and an optional polymorphic +owner+, the publisher.
  #
  # Has its gallery (+software_images+, +images+), kept +releases+ and their
  # +downloads+, kept +external_links+, its +pipeline+ and its +sync_events+; images, links and
  # releases are editable as nested attributes. Filter scopes:
  # +with_statuses+, +with_platform+, +with_category+, +with_owner+ (each a
  # no-op for a blank value) and +search+ (title or name contains the text).
  # Soft-deletable; changes refresh the outlets (shelves) of its platform.
  class Software < ApplicationRecord
    self.table_name = "softwares"

    include SoftDeletable
    include OutletRefreshing

    belongs_to :owner, polymorphic: true, optional: true

    has_many :software_images, -> { ordered }, foreign_key: :software_id, dependent: :destroy
    has_many :images, through: :software_images
    has_many :releases, -> { kept }, foreign_key: :software_id
    has_many :downloads, through: :releases
    has_many :external_links, -> { kept }, foreign_key: :software_id
    has_one :pipeline, -> { kept }, foreign_key: :software_id
    has_many :fork_links, -> { kept }, foreign_key: :software_id, inverse_of: :software
    has_many :sync_events, -> { order(created_at: :desc, id: :desc) }, foreign_key: :software_id, inverse_of: :software

    accepts_nested_attributes_for :software_images, allow_destroy: true
    accepts_nested_attributes_for :external_links, allow_destroy: true
    accepts_nested_attributes_for :releases, allow_destroy: true

    normalizes :category, with: ->(value) { value.to_s.strip.presence }
    normalizes :fork_of_engine, with: ->(value) { WarpEngine::Forks.normalize_url(value) }
    normalizes :fork_of_name, :fork_of_version, :fork_of_repo, with: ->(value) { value.to_s.strip.presence }
    normalizes :shelf_name, with: ->(value) { value.to_s.strip.upcase.presence }

    validates :name, presence: true, uniqueness: true
    validates :title, presence: true
    validates :platform, presence: true, inclusion: { in: ->(_) { WarpEngine::Platform.names } }
    validates :status, inclusion: { in: ->(_) { WarpEngine::SoftwareStatus.keys } }, allow_blank: true
    validates :category, length: { maximum: 64 }, allow_nil: true
    validates :fork_of_name, presence: true, if: -> { fork_of_engine.present? }
    validates :shelf_name, length: { maximum: 32 }, format: { with: WarpEngine::Names::PATTERN },
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

    # Returns the kept external link of kind +source+, or +nil+.
    def source_link
      external_links.detect(&:source?)
    end

    # Whether the developer tools may offer a fork: the author allows it and
    # the source repository is known to be readable without a sign-in.
    def forkable?
      forks_allowed? && source_link&.public == true
    end

    # Whether this software is a fork of another one.
    def fork? = fork_of_engine.present? && fork_of_name.present?

    # Returns every status key (WarpEngine::SoftwareStatus.keys).
    def self.statuses
      WarpEngine::SoftwareStatus.keys
    end

    private

    def outlet_platform
      previous = saved_changes.fetch("platform", [])[0]
      previous.present? && previous != platform ? nil : platform
    end

    def register_category
      WarpEngine::SoftwareCategory.register(category) if saved_change_to_category? && category.present?
    end

    ActiveSupport.run_load_hooks(:warp_engine_software, self)
  end
end
