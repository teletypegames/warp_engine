module WarpEngine
  # Controller concern that marks every response of the engine with its
  # version: the WarpEngine::VERSION_HEADER header carrying WarpEngine::VERSION.
  # Included by WarpEngine::ApiController and by the controllers of the served
  # outlets that do not inherit from it.
  module VersionHeader
    extend ActiveSupport::Concern

    included do
      before_action :set_version_header
    end

    private

    def set_version_header
      response.headers[WarpEngine::VERSION_HEADER] = WarpEngine::VERSION
    end
  end
end
