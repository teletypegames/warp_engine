module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::PlatformLink: id, platform, name, URL,
    # position and timestamps.
    class PlatformLinkSerializer < Blueprinter::Base
      identifier :id
      fields :platform, :name, :url, :position
      include Timestamps
    end
  end
end
