module WarpEngine
  class Api::SoftwareBuildsController < ApiController
    def show
      render json: WarpEngine::BuildsService.new.show(params[:name])
    end
  end
end
