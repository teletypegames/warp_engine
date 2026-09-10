module WarpEngine
  class Api::SoftwareFacetsController < ApiController
    resource_description do
      short "Catalog facets"
    end

    api :GET, "/api/software/facets", "How many softwares each filter value would show"
    desc <<~DESC
      Takes the same filters as `/api/software`. Every count is faceted: it says how many
      softwares the value would show given the *other* filters as they stand, which is
      the number a person asks about when looking at a filter chip. A null category is
      counted under the empty key.
    DESC
    param :owner_id, :number, required: false, desc: "Filter to the softwares of one owner"
    param :status, String, required: false, desc: "Comma-separated status keys"
    param :platform, String, required: false, desc: "One platform name"
    param :category, String, required: false, desc: "One category key"
    param :q, String, required: false, desc: "Text matched against title and name"
    returns code: 200, desc: "Counts per status, platform and category" do
      property :api, Integer, desc: "Shape version of this JSON"
      property :total, Integer, desc: "Softwares matching every filter"
      property :statuses, Hash, desc: "status key => count"
      property :platforms, Hash, desc: "platform => count"
      property :categories, Hash, desc: "category key => count"
    end
    def show
      render json: WarpEngine::SoftwareService.new.facets(
        subject:  current_subject,
        owner_id: params[:owner_id],
        statuses: params[:status].to_s.split(",").map(&:strip).reject(&:blank?),
        platform: params[:platform].presence,
        category: params[:category].presence,
        query:    params[:q].presence
      )
    end
  end
end
