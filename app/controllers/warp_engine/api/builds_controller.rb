module WarpEngine
  class Api::BuildsController < ApiController
    def index
      render json: WarpEngine::BuildsService.new.index
    end
  end
end
