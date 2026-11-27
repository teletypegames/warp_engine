module WarpEngine
  # Model concern that keeps the static feeds (WarpEngine::Feeds,
  # the directories among them) in step with the catalog: after every commit, soft
  # delete and restore it enqueues a WarpEngine::FeedRefreshJob for the
  # feeds carrying the record's platform. The including model overrides the
  # private +feed_platform+ to name that platform; +nil+ (the default)
  # refreshes every feed. Does nothing when the host configures no feed.
  module FeedRefreshing
    extend ActiveSupport::Concern

    included do
      after_commit :refresh_feeds
    end

    # Soft-deletes the record (see WarpEngine::SoftDeletable#soft_delete!), then
    # enqueues the feed refresh. Returns what the soft delete returned.
    def soft_delete!
      super.tap { refresh_feeds }
    end

    # Restores the record (see WarpEngine::SoftDeletable#restore!), then
    # enqueues the feed refresh. Returns what the restore returned.
    def restore!
      super.tap { refresh_feeds }
    end

    private

    def refresh_feeds
      return unless WarpEngine::Feeds.any?

      WarpEngine::FeedRefreshJob.perform_later(feed_platform)
    end

    def feed_platform = nil
  end
end
