module WarpEngine
  module Api
    module Admin
      # Serves the Admin API's OpenAPI 3.1 document and its HTML reference page.
      # When the host sets +openapi_requires_auth+, both need an admin token with
      # the +read+ scope (401 without a token, 403 without the scope).
      class DocumentsController < BaseController
        # <tt>GET <admin path>/openapi.json</tt> and <tt>GET <admin path>/openapi.yaml</tt>.
        #
        # Renders the OpenAPI document of every registered operation, with the
        # server URL of this deployment, as JSON or (for the +yaml+ format) as
        # <tt>application/yaml</tt>.
        def openapi
          authorize_document!
          document = WarpEngine::AdminApi::OpenApi.document(server_url: server_url)

          if params[:format] == "yaml"
            render plain: document.deep_stringify_keys.to_yaml, content_type: "application/yaml"
          else
            render json: document
          end
        end

        # <tt>GET <admin path>/docs</tt>.
        #
        # Renders the HTML API reference page built from the OpenAPI document.
        # Responds 404 unless the host enabled the docs UI.
        def docs
          raise WarpEngine::AdminApi::Error.not_found unless admin_config.docs_ui?

          authorize_document!
          document = WarpEngine::AdminApi::OpenApi.document(server_url: server_url)
          render plain: WarpEngine::AdminApi::DocsPage.render(document), content_type: "text/html"
        end

        private

        def authorize_document!
          return unless admin_config.openapi_requires_auth?

          authenticate!
          return if current_principal.scope?(WarpEngine::AdminApi::Scopes::READ)

          raise WarpEngine::AdminApi::Error.forbidden("This needs the #{WarpEngine::AdminApi::Scopes::READ} scope")
        end
      end
    end
  end
end
