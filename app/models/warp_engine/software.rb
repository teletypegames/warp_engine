module WarpEngine
  class Software < ApplicationRecord
    self.table_name = "softwares"

    # Owner of the publishing token (e.g. AdminUser) — for 3rd-party isolation,
    # see enforce_software_ownership. nil = internal / pre-backfill software.
    belongs_to :owner, polymorphic: true, optional: true

    has_many :software_images, foreign_key: :software_id, dependent: :destroy
    has_many :images, through: :software_images
    has_many :releases, foreign_key: :software_id
    has_many :downloads, through: :releases
    has_many :external_links, foreign_key: :software_id

    accepts_nested_attributes_for :software_images, allow_destroy: true
    accepts_nested_attributes_for :external_links, allow_destroy: true
    accepts_nested_attributes_for :releases, allow_destroy: true

    validates :name, presence: true, uniqueness: true
    validates :title, presence: true
    validates :platform, presence: true

    default_scope { where(deleted_at: nil) }

    def self.ransackable_attributes(auth_object = nil)
      %w[author created_at desc highlighted id license name owner_id owner_type platform site status story title updated_at]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[releases external_links software_images images]
    end

    ActiveSupport.run_load_hooks(:warp_engine_software, self)
  end
end
