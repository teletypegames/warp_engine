module WarpEngine
  module Api
    module Ci
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
