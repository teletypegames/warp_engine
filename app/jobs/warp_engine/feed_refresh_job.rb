module WarpEngine
  # Background job that brings the static feeds in line with the
  # catalog after a change (WarpEngine::FeedRefreshing, a publish), so the
  # request or the save that caused it does not wait for files to be written.
  class FeedRefreshJob < ApplicationJob
    queue_as :default

    # Runs WarpEngine::Feeds.refresh for the feeds carrying +platform+
    # (every static feed when +nil+). A failing feed is logged and
    # left out; the job itself does not fail.
    def perform(platform = nil)
      WarpEngine::Feeds.refresh(platform: platform)
    end
  end
end
