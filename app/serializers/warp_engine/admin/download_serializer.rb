module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::Download: id, file path, release and
    # software ids, IP address, user agent, referer, outlet key, Client-Id and
    # timestamps.
    class DownloadSerializer < Blueprinter::Base
      identifier :id
      field :file_path,  name: :filePath
      field :release_id, name: :releaseId
      field(:softwareId) { |download| download.release&.software_id }
      field :ip_address, name: :ipAddress
      field :user_agent, name: :userAgent
      field :referer
      field :outlet
      field :client_id, name: :clientId
      include Timestamps
    end
  end
end
