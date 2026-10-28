module WarpEngine
  # Reports which build assets the releases of one software have.
  class Api::SoftwareBuildsController < ApiController
    # <tt>GET /api/softwares/:name/builds</tt>.
    #
    # Renders WarpEngine::BuildsService#show: the software's platform, the asset
    # kinds it expects, and for every release version the kinds present and the
    # required ones missing. Responds 404 for an unknown software.
    def show
      render json: WarpEngine::BuildsService.new.show(params[:name])
    end
  end
end
