module WarpEngine
  class Api::SoftwareHighlightedController < ApiController
    resource_description do
      short "Highlighted software"
    end

    api :GET, "/api/software/highlighted", "Get currently highlighted software entry"
    returns code: 200, desc: "Highlighted software with releases and stats" do
      property :software, Hash, desc: "Software entry" do
        property :ID, Integer, desc: "Software ID"
        property :name, String, desc: "Internal name"
        property :title, String, desc: "Display title"
        property :author, String, desc: "Author name"
        property :desc, String, desc: "Short description"
        property :story, String, desc: "Long description / story"
        property :license, String, desc: "License type"
        property :platform, String, desc: "Platform (tic80, love, ebitengine, c64, godot, bevy, phaser)"
        property :status, String, desc: "Status"
        property :highlighted, :boolean, desc: "Highlighted flag"
        property :imageUrl, String, desc: "Default image URL"
      end
      property :releases, Array, desc: "All releases" do
        property :ID, Integer, desc: "Release ID"
        property :version, String, desc: "Version string"
        property :cartridgePath, String, desc: "Cartridge path"
        property :sourcePath, String, desc: "Source path"
        property :htmlFolderPath, String, desc: "HTML folder path"
        property :docsFolderPath, String, desc: "Docs folder path"
        property :downloadCount, Integer, desc: "Download count"
      end
      property :latestRelease, Hash, desc: "Latest release object"
      property :webPlayableRelease, Hash, desc: "Web-playable release (if any)"
      property :totalDownloads, Integer, desc: "Total download count across all releases"
    end
    error code: 404, desc: "No highlighted software found"
    def index
      result = WarpEngine::SoftwareHighlightedService.new.index
      if result
        render json: result
      else
        render json: { error: "no highlighted software found" }, status: :not_found
      end
    end
  end
end
