module WarpEngine
  module Api
    module Admin
      class OperationsController < BaseController
        IGNORED_PARAMS = %w[controller action operation format].freeze

        def execute
          operation = WarpEngine::AdminApi::Registry.find(params[:operation])
          raise WarpEngine::AdminApi::Error.not_found if operation.nil?

          throttle! if current_principal
          result = WarpEngine::AdminApi::Runner.call(
            operation, principal: current_principal, params: operation_params, base_url: engine_base_url, via: :http
          )

          if result.status == 204
            head :no_content
          else
            render json: result.payload, status: result.status
          end
        end

        private

        def operation_params
          params.to_unsafe_h.except(*IGNORED_PARAMS)
        end
      end
    end
  end
end
