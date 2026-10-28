module WarpEngine
  class Configuration
    # The <tt>admin_api do ... end</tt> block of WarpEngine::Configuration::DSL;
    # every method writes one WarpEngine::AdminApi::Configuration setting.
    class AdminApiDSL
      # Creates a DSL writing into the WarpEngine::AdminApi::Configuration +settings+.
      def initialize(settings)
        @settings = settings
      end

      # Turns the admin API on (or off with +false+).
      def enable(value = true) = @settings.enabled = value

      # Turns the MCP endpoint on (or off with +false+).
      def mcp(value = true) = @settings.mcp = value

      # Refuses every write with 405 when +true+.
      def read_only(value = true) = @settings.read_only = value

      # Serves the Redoc documentation page when +true+.
      def docs_ui(value = true) = @settings.docs_ui = value

      # Serves the OpenAPI document without authentication when +true+.
      def public_openapi(value = true) = @settings.openapi_requires_auth = !value

      # Limits each caller to +to+ requests within +per+ seconds.
      def rate_limit(to, per:) = @settings.rate_limit = { to: to, within: per }

      # Names the resources the admin API exposes, or <tt>:all</tt>.
      def resources(*names)
        @settings.resources = names == [ :all ] ? :all : names.flatten.map(&:to_sym)
      end

      # Names the resources the MCP endpoint leaves out.
      def exclude_from_mcp(*names) = @settings.mcp_exclude = names.flatten.map(&:to_sym)

      # Sets the class name of the owner admin tokens belong to.
      def token_owner(class_name) = @settings.token_owner_class = class_name.to_s

      # Sets the authenticator: <tt>:application_token</tt>, or a callable taking
      # the request and returning a WarpEngine::AdminApi::Principal or +nil+.
      def authenticator(value) = @settings.authenticator = value

      # Sets the default list page size.
      def page_size(value) = @settings.page_size = value

      # Sets the largest list page size a caller may ask for.
      def max_page_size(value) = @settings.max_page_size = value
    end
  end
end
