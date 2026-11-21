module WarpEngine
  module Api
    # The forks of the catalog (WarpEngine::Forks): the list of one
    # software's forks, and the announcements other engines send of forks of
    # our softwares.
    class ForksController < ApiController
      resource_description do
        short "Forks"
      end

      api :GET, "/api/softwares/:name/forks", "The forks of a software"
      desc "Its forks on this engine the caller may see, and the forks other engines announced that an administrator let through."
      param :name, String, required: true, desc: "Software name"
      # <tt>GET /api/softwares/:name/forks</tt>: renders +api+, +software+ and
      # +forks+ (WarpEngine::ForkService#forks: +engine+, +name+, +title+,
      # +local+). Responds 404 when the caller may not see the software.
      def index
        scope = WarpEngine.access_policy.visible_software_scope(subject: current_subject)
        software = scope.find_by!(name: params[:name])
        render json: { api: WarpEngine::API_VERSION, software: software.name,
                       forks: WarpEngine::ForkService.new.forks(software, scope: scope) }
      end

      api :POST, "/api/forks", "Announce a fork of one of our softwares"
      desc "Sent by the engine a fork is published on. The fork is read back from that engine's catalog API before it is recorded."
      param :engine, String, required: true, desc: "Base URL of the engine the fork lives on"
      param :name, String, required: true, desc: "The fork's name there"
      # <tt>POST /api/forks</tt>: takes the announcement
      # (WarpEngine::ForkService#receive) and renders 202
      # <tt>{ "status": "accepted" }</tt>; 404 when this engine takes no
      # announcements, 422 for a malformed one, 429 over the rate limit.
      def create
        return render(json: { error: "Not found" }, status: :not_found) unless WarpEngine::Forks.accept_announcements?

        WarpEngine::ForkService.new.receive(engine: params[:engine], name: params[:name], remote_ip: request.remote_ip)
        render json: { status: "accepted" }, status: :accepted
      rescue WarpEngine::ForkService::InvalidAnnouncement => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue WarpEngine::ForkService::RateLimited => e
        render json: { error: e.message }, status: :too_many_requests
      end
    end
  end
end
