module WarpEngine
  module Api
    module Admin
      # Runs the REST operations of the Admin API. Every operation in
      # WarpEngine::AdminApi::Registry is routed here with its key in the
      # +operation+ route default.
      class OperationsController < BaseController
        # Request parameters Rails adds for routing, removed before the parameters
        # reach an operation.
        IGNORED_PARAMS = %w[controller action operation format].freeze

        # Any Admin API operation route, for example <tt>GET <admin path>/softwares</tt>.
        #
        # Looks up the operation (404 when unknown), applies the rate limit when a
        # principal is present, and runs it through WarpEngine::AdminApi::Runner with
        # the request parameters. Renders the result payload as JSON with the
        # result's status, or 204 with no body. Authentication and scope checks are
        # the runner's.
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
