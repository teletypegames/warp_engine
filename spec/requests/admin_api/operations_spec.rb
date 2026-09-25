require "rails_helper"
require "tmpdir"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API vocabulary, statistics, pipelines and files", type: :request do
  include AdminApiHelpers

  describe "software statuses" do
    it "seeds the defaults, then adds, changes and deletes one" do
      api_get "/software_statuses"
      expect(json["data"].map { |s| s["key"] }).to eq(%w[released demo development archived])

      api_post "/software_statuses", { key: "beta", label: "Beta", position: 9, defaultVisible: false }
      id = json["data"]["id"]
      expect(json["data"]).to include("key" => "beta", "softwareCount" => 0, "defaultVisible" => false)

      api_patch "/software_statuses/#{id}", { label: "Open beta" }
      expect(json["data"]["label"]).to eq("Open beta")

      api_get "/software_statuses", params: { defaultVisible: "false" }
      expect(json["data"].map { |s| s["key"] }).to contain_exactly("development", "beta")

      api_delete "/software_statuses/#{id}"
      expect(WarpEngine::SoftwareStatus.exists?(id)).to be(false)
    end

    it "refuses a key the vocabulary cannot hold" do
      api_post "/software_statuses", { key: "Not OK", label: "x" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"]).to have_key("key")
    end
  end

  describe "software categories" do
    it "lists the ones waiting for review and clears the flag" do
      WarpEngine::SoftwareCategory.register("shooter")
      create(:software, category: "shooter")

      api_get "/software_categories", params: { needsReview: "true" }
      category = json["data"].find { |c| c["key"] == "shooter" }
      expect(category).to include("needsReview" => true, "softwareCount" => 1)

      api_patch "/software_categories/#{category['id']}", { label: "Shooter", needsReview: false }
      expect(json["data"]).to include("label" => "Shooter", "needsReview" => false)
    end
  end

  describe "platform links" do
    it "filters by platform" do
      WarpEngine::PlatformLink.create!(platform: "tic80", name: "TIC-80", url: "https://tic80.com")
      WarpEngine::PlatformLink.create!(platform: "love", name: "LÖVE", url: "https://love2d.org")

      api_get "/platform_links", params: { platform: "love" }

      expect(json["data"].map { |l| l["name"] }).to eq([ "LÖVE" ])
    end
  end

  describe "downloads" do
    let(:software) { create(:software, name: "ra", title: "Blessing of Ra") }
    let(:release) { create(:release, software: software, version: "1.0") }

    before do
      create(:download, file_path: "ra-1.0.tic", release: release, user_agent: "curl/8")
      create(:download, file_path: "ra-1.0.tic", release: release, created_at: 2.months.ago)
      create(:download, file_path: "other.zip", ip_address: "10.0.0.9")
    end

    it "lists the log with the admin's filters" do
      api_get "/downloads", params: { software: "Ra" }
      expect(json["data"].size).to eq(2)
      expect(json["data"].first["softwareId"]).to eq(software.id)

      api_get "/downloads", params: { ipAddress: "10.0.0" }
      expect(json["data"].map { |d| d["filePath"] }).to eq(%w[other.zip])

      api_get "/downloads", params: { from: 1.day.ago.iso8601 }
      expect(json["data"].size).to eq(2)

      api_get "/downloads", params: { from: "yesterday" }
      expect(response).to have_http_status(:bad_request)
    end

    it "sums them up like the admin sidebar" do
      api_get "/downloads/summary"
      expect(json["data"]).to eq("total" => 3, "today" => 2, "week" => 2, "month" => 2)

      api_get "/downloads/top_files", params: { limit: 1 }
      expect(json["data"]).to match([ hash_including("filePath" => "ra-1.0.tic", "downloads" => 2) ])

      api_get "/downloads/top_softwares"
      expect(json["data"]).to eq([ { "softwareId" => software.id, "name" => "ra", "title" => "Blessing of Ra", "downloads" => 2 } ])

      api_get "/softwares/#{software.id}/download_stats"
      expect(json["data"]["total"]).to eq(2)
      expect(json["data"]["releases"].first).to include("version" => "1.0", "downloads" => 2)
    end

    it "shows one download" do
      download = WarpEngine::Download.last

      api_get "/downloads/#{download.id}"

      expect(json["data"]["ipAddress"]).to eq("10.0.0.9")
    end
  end

  describe "pipelines" do
    let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter, configured?: true, name: "Woodpecker") }

    before { allow(WarpEngine).to receive(:ci).and_return(ci) }

    it "answers 503 without a CI server" do
      allow(ci).to receive(:configured?).and_return(false)

      api_get "/pipelines"

      expect(response).to have_http_status(:service_unavailable)
      expect(json["error"]).to eq("CI not configured")
    end

    it "lists, links a software, reads runs and triggers" do
      pipeline = create(:pipeline, repo_name: "ra", platform: "tic80")
      software = create(:software)
      run = WarpEngine::CI::Run.new(number: 7, status: "success", branch: "main", created_at: Time.utc(2026, 9, 1))
      allow(ci).to receive(:runs).with(pipeline.remote_repo_id, page: 1).and_return([ run ])
      allow(ci).to receive(:trigger).with(pipeline.remote_repo_id, branch: "dev").and_return(run)

      api_get "/pipelines", params: { active: "true" }
      expect(json["data"].first).to include("repoName" => "ra", "fullName" => "testorg/ra")

      api_patch "/pipelines/#{pipeline.id}", { softwareId: software.id }
      expect(json["data"]["softwareId"]).to eq(software.id)

      api_get "/pipelines/#{pipeline.id}/runs"
      expect(json["data"].first).to include("number" => 7, "status" => "success")
      expect(pipeline.reload.last_pipeline_status).to eq("success")

      api_post "/pipelines/#{pipeline.id}/trigger", { branch: "dev" }
      expect(json["data"]["number"]).to eq(7)
    end

    it "refuses to trigger an inactive pipeline" do
      pipeline = create(:pipeline, :inactive)

      api_post "/pipelines/#{pipeline.id}/trigger"

      expect(response).to have_http_status(:conflict)
    end

    it "answers 502 when the CI server fails" do
      pipeline = create(:pipeline)
      allow(ci).to receive(:runs).and_raise(WarpEngine::CI::ConnectionError, "down")

      api_get "/pipelines/#{pipeline.id}/runs"

      expect(response).to have_http_status(:bad_gateway)
    end

    it "syncs the repositories" do
      allow(ci).to receive(:repos).and_return([ WarpEngine::CI::Repo.new(id: 4242, name: "fresh", owner: "org", active: true) ])

      api_post "/pipelines/sync"

      expect(json["data"]["created"].map { |p| p["repoName"] }).to eq(%w[fresh])
    end
  end

  describe "files" do
    let(:container) { Dir.mktmpdir("admin-api-files") }

    before do
      FileUtils.mkdir_p(File.join(container, "game-1.0"))
      File.write(File.join(container, "game-1.0.zip"), "zip")
      create(:download, file_path: "game-1.0.zip")
      allow(WarpEngine.config).to receive(:file_container_path).and_return(container)
    end

    after { FileUtils.rm_rf(container) }

    it "lists a directory with the download counts" do
      api_get "/files"

      expect(json["data"].map { |e| [ e["name"], e["type"], e["downloads"] ] })
        .to eq([ [ "game-1.0", "directory", nil ], [ "game-1.0.zip", "file", 1 ] ])
    end

    it "uploads, creates a directory, renames and deletes" do
      upload = Rack::Test::UploadedFile.new(StringIO.new("data"), "application/zip", original_filename: "new.zip")
      post "/api/admin/v1/files", params: { dir: "game-1.0", file: upload }, headers: auth
      expect(response).to have_http_status(:created)
      conform!
      expect(json["data"]["path"]).to eq("game-1.0/new.zip")

      api_post "/files/directories", { name: "docs" }
      expect(json["data"]["path"]).to eq("docs")

      api_patch "/files", { path: "docs", newName: "manual" }
      expect(File.directory?(File.join(container, "manual"))).to be(true)

      api_delete "/files", params: { path: "manual" }
      expect(response).to have_http_status(:no_content)
      expect(File.exist?(File.join(container, "manual"))).to be(false)
    end

    it "will not delete a directory that is not empty" do
      File.write(File.join(container, "game-1.0", "a.txt"), "a")

      api_delete "/files", params: { path: "game-1.0" }

      expect(response).to have_http_status(:conflict)
    end

    it "will not leave the artifact store" do
      api_get "/files", params: { dir: "../../etc" }

      expect(response).to have_http_status(:not_found).or have_http_status(:bad_request)
    end
  end
end
