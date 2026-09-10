module WarpEngine
  class Software < ApplicationRecord
    self.table_name = "softwares"

    STATUSES = %w[development demo released archived].freeze

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
    validates :status, inclusion: { in: STATUSES }, allow_blank: true
    validates :category, length: { maximum: 64 }, allow_nil: true

    ActiveSupport.run_load_hooks(:warp_engine_software, self)
  end
end
