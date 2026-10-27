module WarpEngine
  class Configuration
    class AdminApiDSL
      def initialize(settings)
        @settings = settings
      end

      def enable(value = true) = @settings.enabled = value

      def mcp(value = true) = @settings.mcp = value

      def read_only(value = true) = @settings.read_only = value

      def docs_ui(value = true) = @settings.docs_ui = value

      def public_openapi(value = true) = @settings.openapi_requires_auth = !value

      def rate_limit(to, per:) = @settings.rate_limit = { to: to, within: per }

      def resources(*names)
        @settings.resources = names == [ :all ] ? :all : names.flatten.map(&:to_sym)
      end

      def exclude_from_mcp(*names) = @settings.mcp_exclude = names.flatten.map(&:to_sym)

      def token_owner(class_name) = @settings.token_owner_class = class_name.to_s

      def authenticator(value) = @settings.authenticator = value

      def page_size(value) = @settings.page_size = value

      def max_page_size(value) = @settings.max_page_size = value
    end
  end
end
