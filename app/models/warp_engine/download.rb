module WarpEngine
  # One recorded download of a file: its +file_path+, the +release+ it
  # belongs to when known, and the caller's IP address, user agent and
  # referer. Soft-deletable.
  class Download < ApplicationRecord
    include SoftDeletable

    belongs_to :release, optional: true

    validates :file_path, presence: true

    ActiveSupport.run_load_hooks(:warp_engine_download, self)
  end
end
