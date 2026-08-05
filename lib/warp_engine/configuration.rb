module WarpEngine
  class Configuration
    # Owner kontraktus az image_owners elemeire:
    #   label:       String
    #   image_ids:   -> { Array<Integer> }         — az owner által használt image id-k
    #   usage_label: ->(image) { String vagy nil } — megjelenítendő címke, ha használja
    # update_secret_source: a /update endpoint hitelesítési forrása, kizárólagos.
    #   :env      — a shared secret (update_secret) érvényes, a DB-tokenek nem
    #   :database — csak WarpEngine::ApplicationToken érvényes, a shared secret nem
    # application_token_owner_class: a tokenek kötelező tulajdonosának osztályneve
    # (pl. "AdminUser"); nil esetén a :database mód minden kérést elutasít.
    attr_accessor :file_container_path,
                  :image_container_path,
                  :update_secret,
                  :update_secret_source,
                  :application_token_owner_class,
                  :image_owners

    def initialize
      @file_container_path           = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @image_container_path          = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
      @update_secret                 = ENV["UPDATE_SECRET"]
      @update_secret_source          = :env
      @application_token_owner_class = nil
      @image_owners                  = []
    end
  end
end
