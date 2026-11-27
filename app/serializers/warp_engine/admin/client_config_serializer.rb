module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::ClientConfig: id, client, the settings
    # the host made (+null+ where the default holds) and timestamps.
    class ClientConfigSerializer < Blueprinter::Base
      identifier :id
      fields :client, :name, :subfolder, :statuses
      field :software_name, name: :softwareName
      field :store_key, name: :storeKey
      field :logo_urls, name: :logoUrls
      field :pinned_version, name: :pinnedVersion
      include Timestamps
    end
  end
end
