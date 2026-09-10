module WarpEngine
  class Software < ApplicationRecord
    self.table_name = "softwares"

    include SoftDeletable

    belongs_to :owner, polymorphic: true, optional: true

    has_many :software_images, -> { ordered }, foreign_key: :software_id, dependent: :destroy
    has_many :images, through: :software_images
    has_many :releases, -> { kept }, foreign_key: :software_id
    has_many :downloads, through: :releases
    has_many :external_links, -> { kept }, foreign_key: :software_id
    has_one :pipeline, -> { kept }, foreign_key: :software_id

    accepts_nested_attributes_for :software_images, allow_destroy: true
    accepts_nested_attributes_for :external_links, allow_destroy: true
    accepts_nested_attributes_for :releases, allow_destroy: true

    normalizes :category, with: ->(value) { value.to_s.strip.presence }

    validates :name, presence: true, uniqueness: true
    validates :title, presence: true
    validates :platform, presence: true, inclusion: { in: WarpEngine::Platform::NAMES }
    validates :status, inclusion: { in: ->(_) { WarpEngine::SoftwareStatus.keys } }, allow_blank: true
    validates :category, length: { maximum: 64 }, allow_nil: true

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

    def self.statuses
      WarpEngine::SoftwareStatus.keys
    end

    private

    def register_category
      WarpEngine::SoftwareCategory.register(category) if saved_change_to_category? && category.present?
    end

    ActiveSupport.run_load_hooks(:warp_engine_software, self)
  end
end
