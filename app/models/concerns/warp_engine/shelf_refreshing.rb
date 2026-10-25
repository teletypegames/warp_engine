module WarpEngine
  module ShelfRefreshing
    extend ActiveSupport::Concern

    included do
      after_commit :refresh_shelves
    end

    def soft_delete!
      super.tap { refresh_shelves }
    end

    def restore!
      super.tap { refresh_shelves }
    end

    private

    def refresh_shelves
      return unless WarpEngine::Shelves.any?

      WarpEngine::Shelves.refresh(platform: shelf_platform)
    end

    def shelf_platform = nil
  end
end
