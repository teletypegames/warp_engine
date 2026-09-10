module WarpEngine
  class Api::SoftwareVocabularyController < ApiController
    resource_description do
      short "Catalog vocabulary"
    end

    api :GET, "/api/software/vocabulary", "The statuses and categories this catalog uses, with labels and order"
    desc <<~DESC
      The words a software's `status` and `category` may hold, as the host names and
      orders them. A client draws its filters from here rather than from a list of its
      own, so a host can add a status or rename a category without a client release.
      `defaultVisible` says which statuses a store lists when it has no preference of its
      own; `count` says how many visible softwares carry a category.
    DESC
    returns code: 200, desc: "Statuses and categories" do
      property :api, Integer, desc: "Shape version of this JSON"
      property :statuses, Array, desc: "In display order" do
        property :key, String, desc: "The value a software's status holds"
        property :label, String, desc: "What to call it"
        property :position, Integer, desc: "Display order"
        property :defaultVisible, :boolean, desc: "Listed by default"
        property :badge, String, desc: "A style hint for the label, or null"
      end
      property :categories, Array, desc: "In display order" do
        property :key, String, desc: "The value a software's category holds"
        property :label, String, desc: "What to call it"
        property :position, Integer, desc: "Display order"
        property :count, Integer, desc: "Visible softwares carrying it"
      end
    end
    def show
      render json: WarpEngine::SoftwareService.new.vocabulary(subject: current_subject)
    end
  end
end
