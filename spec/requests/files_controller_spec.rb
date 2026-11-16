require "rails_helper"
require "tmpdir"

RSpec.describe "GET /file/*path", type: :request do
  let(:container) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, storage_adapter: :local)
    WarpEngine::Storage.reset!
    FileUtils.mkdir_p(File.join(container, "game-1.0"))
    File.write(File.join(container, "game-1.0", "index.html"), "<h1>hi</h1>")
  end

  after do
    FileUtils.rm_rf(container)
    WarpEngine::Storage.reset!
  end

  it "redirects a folder to its index page under the engine's routes" do
    get "/file/game-1.0"

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/file/game-1.0/index.html")
  end

  it "sends the index page inline" do
    get "/file/game-1.0/index.html"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<h1>hi</h1>")
  end
end
