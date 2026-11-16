module WarpEngine
  # Background job that brings the materialized outlets in line with the
  # catalog after a change (WarpEngine::OutletRefreshing, a publish), so the
  # request or the save that caused it does not wait for files to be written.
  class OutletRefreshJob < ApplicationJob
    queue_as :default

    # Runs WarpEngine::Outlets.refresh for the outlets carrying +platform+
    # (every materialized outlet when +nil+). A failing outlet is logged and
    # left out; the job itself does not fail.
    def perform(platform = nil)
      WarpEngine::Outlets.refresh(platform: platform)
    end
  end
end
