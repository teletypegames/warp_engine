module WarpEngine
  class Configuration

    attr_accessor :file_container_path,
                  :image_container_path,
                  :update_secret,
                  :application_token_source,
                  :application_token_owner_class,
                  :max_upload_size,
                  :enforce_software_ownership,
                  :ci_platforms,
                  :ci_extension_public_key,
                  :ci_extension_public_key_url,
                  :ci_update_server,
                  :woodpecker_url,
                  :woodpecker_api_token,
                  :woodpecker_repo_owner,
                  :image_owners,
                  :storage_adapter,
                  :access_policy,
                  :access_token_owner_class,
                  :subject_resolver,
                  :identity_verification_url,
                  :device_code_ttl,
                  :device_code_interval

    def initialize
      @file_container_path           = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @image_container_path          = ENV.fetch("IMAGE_CONTAINER_PATH", "/images")
      @update_secret                 = ENV["UPDATE_SECRET"]
      @application_token_source      = :env
      @application_token_owner_class = nil
      @max_upload_size               = 500 * 1024 * 1024
      @enforce_software_ownership    = false
      @ci_platforms                  = {}
      @ci_extension_public_key       = nil
      @ci_extension_public_key_url   = nil
      @ci_update_server              = nil
      @woodpecker_url                = ENV["WOODPECKER_URL"]
      @woodpecker_api_token          = ENV["WOODPECKER_API_TOKEN"]
      @woodpecker_repo_owner         = ENV["WOODPECKER_REPO_OWNER"]
      @image_owners                  = []
      @storage_adapter               = :local
      @access_policy                 = :open
      @access_token_owner_class      = nil
      @subject_resolver              = nil
      @identity_verification_url     = nil
      @device_code_ttl               = 600
      @device_code_interval          = 5
    end
  end
end
