module WarpEngine
  class Api::SoftwareController < ApiController
    resource_description do
      short "Software catalog"
    end

    def_param_group :external_link do
      property :ID, Integer, desc: "Link ID"
      property :softwareId, Integer, desc: "Parent software ID"
      property :label, String, desc: "Link label (e.g. GitHub)"
      property :url, String, desc: "Link URL"
    end

    def_param_group :software_image do
      property :url, String, desc: "Image URL (e.g. /api/image/123)"
      property :isDefault, :boolean, desc: "Default image flag"
      property :position, Integer, desc: "Display order"
    end

    def_param_group :release do
      property :ID, Integer, desc: "Release ID"
      property :softwareId, Integer, desc: "Parent software ID"
      property :version, String, desc: "Version string"
      property :cartridgePath, String, desc: "Cartridge file path"
      property :sourcePath, String, desc: "Source file path"
      property :htmlFolderPath, String, desc: "HTML playable folder path"
      property :docsFolderPath, String, desc: "Documentation folder path"
      property :downloadCount, Integer, desc: "Download count for this release"
    end

    api :GET, "/api/software", "List all software entries with releases"
    param :owner_id, :number, required: false, desc: "Filter to the softwares of one owner (publisher)"
    returns code: 200, desc: "Wrapper object with softwares array" do
      property :softwares, Array, desc: "Array of software entries" do
        property :ID, Integer, desc: "Software ID"
        property :name, String, desc: "Internal name"
        property :title, String, desc: "Display title"
        property :author, String, desc: "Author name"
        property :desc, String, desc: "Short description"
        property :story, String, desc: "Long description / story"
        property :license, String, desc: "License type"
        property :platform, String, desc: "Platform (tic80, love, ebitengine, c64, godot, bevy, phaser)"
        property :status, String, desc: "Status (active, inactive)"
        property :highlighted, :boolean, desc: "Currently highlighted"
        property :imageUrl, String, desc: "Default image URL"
        property :externalLinks, Array, desc: "External links" do
          property :ID, Integer, desc: "Link ID"
          property :label, String, desc: "Link label"
          property :url, String, desc: "Link URL"
        end
        property :images, Array, desc: "Image gallery" do
          property :url, String, desc: "Image URL"
          property :isDefault, :boolean, desc: "Default image flag"
          property :position, Integer, desc: "Display order"
        end
      end
    end
    def index
      render json: WarpEngine::SoftwareService.new.index(owner_id: params[:owner_id], subject: current_subject)
    end
  end
end
