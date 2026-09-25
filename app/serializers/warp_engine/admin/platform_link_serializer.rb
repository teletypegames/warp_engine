module WarpEngine
  module Admin
    class PlatformLinkSerializer < Blueprinter::Base
      identifier :id
      fields :platform, :name, :url, :position
      include Timestamps
    end
  end
end
