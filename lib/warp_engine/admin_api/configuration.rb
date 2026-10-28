module WarpEngine
  module AdminApi
    # The Admin API settings of the host, set in the <tt>admin_api</tt> block of
    # <tt>WarpEngine.configure</tt> (WarpEngine::Configuration::AdminApiDSL) and read
    # through AdminApi.config.
    class Configuration
      # The resources left out of the MCP tools unless the host says otherwise.
      DEFAULT_MCP_EXCLUDE = %i[application_tokens device_grants].freeze

      # The settings:
      #
      # [enabled]               serve the Admin API at all (default +false+)
      # [token_owner_class]     the class name owning admin tokens; defaults to the
      #                         engine's application token owner class
      # [authenticator]         <tt>:application_token</tt>, or a callable taking the
      #                         request and returning a Principal or +nil+
      # [resources]             <tt>:all</tt>, or the names of the resources to serve
      # [read_only]             refuse every write with 405 (default +false+)
      # [page_size]             entries per page by default (50)
      # [max_page_size]         the largest +perPage+ allowed (200)
      # [rate_limit]            <tt>{ to:, within: }</tt> requests per seconds, or +nil+
      # [openapi_requires_auth] whether the OpenAPI document needs a token (default +true+)
      # [docs_ui]               serve the Redoc page (default +false+)
      # [mcp]                   serve the MCP endpoint (default +false+)
      # [mcp_exclude]           resource names left out of MCP
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

      # Sets the defaults listed above.
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

      # Whether the Admin API is on.
      def enabled? = enabled == true
      # Whether writes are refused.
      def read_only? = read_only == true
      # Whether the MCP endpoint is served; needs #enabled? too.
      def mcp? = enabled? && mcp == true
      # Whether the Redoc documentation page is served.
      def docs_ui? = docs_ui == true
      # Whether the OpenAPI document needs a token; only an explicit +false+ opens it.
      def openapi_requires_auth? = openapi_requires_auth != false

      # The class name of admin token owners, or +nil+ when neither it nor the engine default is set.
      def owner_class_name
        (token_owner_class.presence || WarpEngine.config.application_token_owner_class).presence&.to_s
      end

      # Whether the resource named +name+ is served under #resources.
      def resource_enabled?(name)
        return true if resources.nil? || resources == :all

        Array(resources).map(&:to_sym).include?(name.to_sym)
      end

      # Whether the resource named +name+ is left out of the MCP tools.
      def mcp_excluded?(name)
        Array(mcp_exclude).map(&:to_sym).include?(name.to_sym)
      end
    end
  end
end
