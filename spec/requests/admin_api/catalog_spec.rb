require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API catalog", type: :request do
  include AdminApiHelpers

  describe "softwares" do
    it "lists a page at a time with the paging in meta" do
      create_list(:software, 3)
      admin_config.page_size = 2

      api_get "/softwares"

      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to eq("page" => 1, "perPage" => 2, "total" => 3, "totalPages" => 2, "nextPage" => 2)

      api_get "/softwares", params: { page: 2 }
      expect(json["data"].size).to eq(1)
      expect(json["meta"]["nextPage"]).to be_nil
    end

    it "caps the page size at the host's ceiling" do
      admin_config.max_page_size = 5

      api_get "/softwares", params: { perPage: 500 }

      expect(json["meta"]["perPage"]).to eq(5)
    end

    it "filters like the admin does and leaves the soft-deleted out" do
      create(:software, name: "alpha", title: "Alpha", platform: "love", highlighted: true)
      create(:software, name: "beta", title: "Beta", platform: "tic80")
      create(:software, name: "gone", title: "Gone", deleted_at: Time.current)

      api_get "/softwares", params: { platform: "love" }
      expect(json["data"].map { |s| s["name"] }).to eq(%w[alpha])

      api_get "/softwares", params: { q: "bet" }
      expect(json["data"].map { |s| s["name"] }).to eq(%w[beta])

      api_get "/softwares", params: { highlighted: "false" }
      expect(json["data"].map { |s| s["name"] }).to eq(%w[beta])

      api_get "/softwares", params: { title: "ph" }
      expect(json["data"].map { |s| s["name"] }).to eq(%w[alpha])
    end

    it "sorts by an allowed key, and refuses another" do
      create(:software, name: "b", title: "B")
      create(:software, name: "a", title: "A")

      api_get "/softwares", params: { sort: "-title" }
      expect(json["data"].map { |s| s["title"] }).to eq(%w[B A])

      api_get "/softwares", params: { sort: "author" }
      expect(response).to have_http_status(:bad_request)
    end

    it "creates, shows, changes and deletes one" do
      api_post "/softwares", { name: "newgame", title: "New Game", platform: "tic80", status: "demo",
                               category: "puzzle", desc: "Short" }
      expect(response).to have_http_status(:created)
      id = json["data"]["id"]
      expect(json["data"]).to include("name" => "newgame", "status" => "demo", "category" => "puzzle")
      expect(WarpEngine::SoftwareCategory.find_by(key: "puzzle")&.needs_review).to be(true)

      api_patch "/softwares/#{id}", { title: "Renamed", highlighted: true }
      expect(json["data"]).to include("title" => "Renamed", "highlighted" => true, "name" => "newgame")

      api_get "/softwares/#{id}"
      expect(json["data"]["title"]).to eq("Renamed")

      api_delete "/softwares/#{id}"
      expect(response).to have_http_status(:no_content)
      expect(WarpEngine::Software.exists?(id)).to be(false)
    end

    it "answers a failed validation with 422 and the fields" do
      create(:software, name: "taken")

      api_post "/softwares", { name: "taken", title: "", platform: "amiga" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("Validation failed")
      expect(json["details"].keys).to include("name", "title", "platform")
    end

    it "ignores fields the API does not take" do
      api_post "/softwares", { name: "sly", title: "Sly", platform: "tic80", ownerId: 99, deletedAt: Time.current }

      software = WarpEngine::Software.find(json["data"]["id"])
      expect(software.owner_id).to be_nil
      expect(software.deleted_at).to be_nil
    end

    it "includes what belongs to a software when asked" do
      software = create(:software)
      release = create(:release, software: software, version: "1.0")
      release.release_assets.create!(kind: "cartridge", path: "/softwares/x.tic")
      software.external_links.create!(label: "Repo", url: "https://example.org")

      api_get "/softwares/#{software.id}", params: { include: "releases,externalLinks,images" }

      expect(json["data"]["releases"].first["assets"].first["kind"]).to eq("cartridge")
      expect(json["data"]["externalLinks"].first["label"]).to eq("Repo")
      expect(json["data"]["images"]).to eq([])

      api_get "/softwares/#{software.id}", params: { include: "everything" }
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 404 for a missing or soft-deleted software" do
      gone = create(:software, deleted_at: Time.current)

      api_get "/softwares/#{gone.id}"
      expect(response).to have_http_status(:not_found)

      api_get "/softwares/0"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "releases and assets" do
    let(:software) { create(:software, platform: "tic80") }

    it "adds a release, an asset to it, and removes both" do
      api_post "/softwares/#{software.id}/releases", { version: "2.0" }
      expect(response).to have_http_status(:created)
      release_id = json["data"]["id"]

      api_post "/releases/#{release_id}/assets", { kind: "cartridge", path: "/softwares/game-2.0.tic" }
      expect(response).to have_http_status(:created)
      asset_id = json["data"]["id"]

      api_get "/releases/#{release_id}/assets"
      expect(json["data"].map { |a| a["kind"] }).to eq(%w[cartridge])

      api_patch "/assets/#{asset_id}", { path: "/softwares/game-2.0b.tic" }
      expect(json["data"]["path"]).to eq("/softwares/game-2.0b.tic")

      api_get "/softwares/#{software.id}/releases"
      expect(json["data"].first["assets"].size).to eq(1)

      api_delete "/assets/#{asset_id}"
      expect(response).to have_http_status(:no_content)

      api_delete "/releases/#{release_id}"
      expect(WarpEngine::Release.exists?(release_id)).to be(false)
    end

    it "refuses a duplicate version" do
      create(:release, software: software, version: "1.0")

      api_post "/softwares/#{software.id}/releases", { version: "1.0" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"]).to have_key("version")
    end

    it "refuses an html asset for a download-only platform" do
      allow_any_instance_of(WarpEngine::Platform).to receive(:expected_kinds).and_return(%w[cartridge])
      release = create(:release, software: create(:software, platform: "c64"))

      api_post "/releases/#{release.id}/assets", { kind: "html", path: "/softwares/g/html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"]["kind"].first).to include("download only")
    end
  end

  describe "external links" do
    it "adds, changes and removes one" do
      software = create(:software)

      api_post "/softwares/#{software.id}/external_links", { label: "Itch", url: "https://itch.io/x" }
      id = json["data"]["id"]

      api_patch "/external_links/#{id}", { label: "itch.io" }
      expect(json["data"]["label"]).to eq("itch.io")

      api_get "/softwares/#{software.id}/external_links"
      expect(json["data"].size).to eq(1)

      api_delete "/external_links/#{id}"
      expect(WarpEngine::ExternalLink.exists?(id)).to be(false)
    end
  end

  describe "software images" do
    let(:software) { create(:software) }

    it "links a library image, makes it the default and unlinks it" do
      first = create(:image)
      second = create(:image)

      api_post "/softwares/#{software.id}/images", { imageId: first.id, isDefault: true }
      first_id = json["data"]["id"]
      expect(json["data"]).to include("position" => 1, "isDefault" => true, "url" => "/api/image/#{first.id}")

      api_post "/softwares/#{software.id}/images", { imageId: second.id }
      second_id = json["data"]["id"]
      expect(json["data"]["position"]).to eq(2)

      api_patch "/software_images/#{second_id}", { isDefault: true }
      api_get "/softwares/#{software.id}/images"
      expect(json["data"].map { |i| [ i["id"], i["isDefault"] ] }).to eq([ [ first_id, false ], [ second_id, true ] ])

      api_delete "/software_images/#{first_id}"
      expect(WarpEngine::SoftwareImage.exists?(first_id)).to be(false)
    end

    it "uploads a new image into the library" do
      upload = Rack::Test::UploadedFile.new(StringIO.new("png"), "image/png", original_filename: "cover.png")

      post "/api/admin/v1/softwares/#{software.id}/images/upload", params: { file: upload, isDefault: "true" },
                                                                  headers: auth

      expect(response).to have_http_status(:created)
      conform!
      image = Image.find(json["data"]["imageId"])
      expect(image.original_filename).to eq("cover.png")
      expect(json["data"]["isDefault"]).to be(true)
    end

    it "refuses an image that is not in the library" do
      api_post "/softwares/#{software.id}/images", { imageId: 0 }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "additional resources" do
    let(:software) { create(:software) }
    let(:extra) do
      WarpEngine::AdditionalResource.new(
        subject: :software, association: :external_links, label: "Links", permitted: %i[id label url _destroy],
        fields: ->(form) { form },
        api_schema: { type: "object", properties: { id: { type: "integer" }, label: { type: "string" },
                                                    url: { type: "string" } } }
      )
    end

    around do |example|
      previous = WarpEngine.config.additional_resources
      WarpEngine.config.additional_resources = [ extra ]
      example.run
      WarpEngine.config.additional_resources = previous
    end

    it "reads and replaces an extra through nested attributes" do
      link = software.external_links.create!(label: "Old", url: "https://old.example")

      api_patch "/softwares/#{software.id}/extras/external_links",
                { value: [ { id: link.id, _destroy: true }, { label: "New", url: "https://new.example" } ] }
      expect(response).to have_http_status(:ok)
      expect(json["data"]["value"].map { |l| l["label"] }).to eq(%w[New])

      api_get "/softwares/#{software.id}/extras/external_links"
      expect(json["data"]).to include("association" => "external_links", "multiple" => true)

      api_get "/softwares/#{software.id}", params: { include: "extras" }
      expect(json["data"]["extras"]["external_links"].first["label"]).to eq("New")
    end

    it "answers 404 for an extra without an API schema, or an unknown one" do
      api_get "/softwares/#{software.id}/extras/software_images"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a value of the wrong shape" do
      api_patch "/softwares/#{software.id}/extras/external_links", { value: { label: "x" } }

      expect(response).to have_http_status(:bad_request)
    end

    it "has no extras at all where no extra has an API schema" do
      WarpEngine.config.additional_resources = []

      api_get "/softwares/#{software.id}/extras/external_links"

      expect(response).to have_http_status(:not_found)
    end
  end
end
