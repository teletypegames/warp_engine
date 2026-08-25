module WarpEngine
  class Download < ApplicationRecord
    include SoftDeletable

    belongs_to :release, optional: true

    validates :file_path, presence: true

    ActiveSupport.run_load_hooks(:warp_engine_download, self)
  end
end
