require "rails_helper"

RSpec.describe "GET /api/stores/:client/*", type: :request do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    engine = create(:software, name: "we-retroarch", platform: "retroarch")
    path = File.join(tmpdir, "softwares/we-retroarch/1.3.0/we-retroarch-1.3.0.tar.gz")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "archive")
    create(:release, software: engine, version: "1.3.0").release_assets.create!(kind: "package", path: path)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "answers the release a machine runs" do
    get "/api/stores/retroarch/release"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq(
      "software" => "we-retroarch", "version" => "1.3.0", "size" => 7,
      "url" => "/api/download?path=softwares%2Fwe-retroarch%2F1.3.0%2Fwe-retroarch-1.3.0.tar.gz"
    )
  end

  it "serves the store config with this catalog and the release path" do
    get "/api/stores/retroarch/config.json"

    config = JSON.parse(response.body)
    expect(config["store"]).to include("base_url" => "http://www.example.com", "id" => "example")
    expect(config.dig("store", "api", "release")).to eq("/api/stores/retroarch/release")
  end

  it "serves the installer as a shell script" do
    get "/api/stores/retroarch/install.sh"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/x-shellscript")
    expect(response.body).to include("we-retroarch 1.3.0", "http://www.example.com/api/stores/retroarch/config.json",
                                     "http://www.example.com/api/download?path=softwares%2Fwe-retroarch")
  end

  it "has nothing for a store engine without a release, nor for an unknown one" do
    get "/api/stores/batocera/install.sh"
    expect(response).to have_http_status(:not_found)

    get "/api/stores/pegasus/install.sh"
    expect(response).to have_http_status(:not_found)
  end
end
