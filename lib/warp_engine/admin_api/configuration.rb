module WarpEngine
  module AdminApi
    class Configuration
      DEFAULT_MCP_EXCLUDE = %i[application_tokens device_grants].freeze

      attr_accessor :enabled,
                    :token_owner_class,
                    :authenticator,
                    :resources,
                    :read_only,
                    :page_size,
                    :max_page_size,
                    :rate_limit,
                    :openapi_requires_auth,
                    :docs_ui,
                    :mcp,
                    :mcp_exclude

      def initialize
        @enabled               = false
        @token_owner_class     = nil
        @authenticator         = :application_token
        @resources             = :all
        @read_only             = false
        @page_size             = 50
        @max_page_size         = 200
        @rate_limit            = nil
        @openapi_requires_auth = true
        @docs_ui               = false
        @mcp                   = false
        @mcp_exclude           = DEFAULT_MCP_EXCLUDE
      end

      def enabled? = enabled == true
      def read_only? = read_only == true
      def mcp? = enabled? && mcp == true
      def docs_ui? = docs_ui == true
      def openapi_requires_auth? = openapi_requires_auth != false

      def owner_class_name
        (token_owner_class.presence || WarpEngine.config.application_token_owner_class).presence&.to_s
      end

      def resource_enabled?(name)
        return true if resources.nil? || resources == :all

        Array(resources).map(&:to_sym).include?(name.to_sym)
      end

      def mcp_excluded?(name)
        Array(mcp_exclude).map(&:to_sym).include?(name.to_sym)
      end
    end
  end
end
