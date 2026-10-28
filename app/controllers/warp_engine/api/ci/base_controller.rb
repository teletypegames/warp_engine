module WarpEngine
  module Api
    # Namespace of the CI pipeline endpoints under <tt>/api/ci</tt>.
    module Ci
      # Base controller of the CI pipeline endpoints. Responds 503
      # <tt>{ "error": "CI not configured" }</tt> when no CI adapter is configured.
      class BaseController < WarpEngine::ApiController
        before_action :require_ci!

        private

        def require_ci!
          return if WarpEngine.ci.configured?

          render json: { error: "CI not configured" }, status: :service_unavailable
        end

        def pipeline_scope = WarpEngine::Pipeline.all
      end
    end
  end
end
