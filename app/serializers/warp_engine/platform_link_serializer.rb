module WarpEngine
  # Catalog view of a WarpEngine::PlatformLink: name and URL.
  class PlatformLinkSerializer < Blueprinter::Base
    field :name
    field :url
  end
end
