module WarpEngine
  class Configuration
    # Owner kontraktus az image_owners elemeire:
    #   label:       String
    #   image_ids:   -> { Array<Integer> }         — az owner által használt image id-k
    #   usage_label: ->(image) { String vagy nil } — megjelenítendő címke, ha használja
    attr_accessor :file_container_path,
                  :image_container_path,
                  :update_secret,
                  :image_owners

    def initialize
      @file_container_path  = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @image_container_path = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
      @update_secret        = ENV["UPDATE_SECRET"]
      @image_owners         = []
    end
  end
end
