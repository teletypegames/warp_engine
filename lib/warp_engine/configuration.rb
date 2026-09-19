module WarpEngine
  class Configuration
    attr_accessor :site_url,
                  :file_container_path,
                  :update_secret,
                  :application_token_source,
                  :application_token_owner_class,
                  :max_upload_size,
                  :enforce_software_ownership,
                  :ci_adapter,
                  :image_class_name,
                  :image_adapter,
                  :storage_adapter,
                  :access_policy,
                  :access_token_owner_class,
                  :subject_resolver,
                  :identity_verification_url,
                  :device_code_ttl,
                  :device_code_interval,
                  :ignored_user_agents,
                  :catalog_page_size,
                  :catalog_max_page_size,
                  :additional_resources

    def initialize
      @site_url                      = nil
      @file_container_path           = ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
      @update_secret                 = ENV["UPDATE_SECRET"]
      @application_token_source      = :env
      @application_token_owner_class = nil
      @max_upload_size               = 500 * 1024 * 1024
      @enforce_software_ownership    = false
      @ci_adapter                    = :woodpecker
      @image_class_name              = "Image"
      @image_adapter                 = nil
      @storage_adapter               = :local
      @access_policy                 = :open
      @access_token_owner_class      = nil
      @subject_resolver              = nil
      @identity_verification_url     = nil
      @device_code_ttl               = 600
      @device_code_interval          = 5
      @ignored_user_agents           = []
      @catalog_page_size             = 48
      @catalog_max_page_size         = 200
      @additional_resources          = []
    end

    def ignored_user_agent?(ua)
      return false if ua.blank?

      @_ignored_ua_patterns ||= Array(@ignored_user_agents).map do |pattern|
        pattern.is_a?(Regexp) ? pattern : Regexp.new("\\A#{Regexp.escape(pattern).gsub("\\*", ".*")}\\z", Regexp::IGNORECASE)
      end

      @_ignored_ua_patterns.any? { |re| re.match?(ua) }
    end

    def ignored_user_agents=(value)
      @ignored_user_agents = value
      @_ignored_ua_patterns = nil
    end
  end
end
