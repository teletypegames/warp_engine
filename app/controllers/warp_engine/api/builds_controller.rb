module WarpEngine
  # Describes the build asset kinds the platforms expect.
  class Api::BuildsController < ApiController
    # <tt>GET /api/builds</tt>.
    #
    # Renders WarpEngine::BuildsService#index: every platform with its label and
    # its expected, required and optional asset kinds, plus +allKinds+, every
    # kind a release asset may have.
    def index
      render json: WarpEngine::BuildsService.new.index
    end
  end
end
