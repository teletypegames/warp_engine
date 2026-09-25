module WarpEngine
  module Api
    module Admin
      class DocumentsController < BaseController
        def openapi
          authorize_document!
          document = WarpEngine::AdminApi::OpenApi.document(server_url: server_url)

          if params[:format] == "yaml"
            render plain: document.deep_stringify_keys.to_yaml, content_type: "application/yaml"
          else
            render json: document
          end
        end

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
