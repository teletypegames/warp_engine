require "rails_helper"

RSpec.describe "GET /.well-known/warp-engine", type: :request do
  def well_known
    get "/.well-known/warp-engine"
    JSON.parse(response.body)
  end

  it "tells a server engine, its version and how a tool signs in" do
    body = well_known

    expect(response).to have_http_status(:ok)
    expect(body).to include("engine" => "warp-engine", "version" => WarpEngine::VERSION, "api" => WarpEngine::API_VERSION,
                            "name" => "www.example.com", "profile" => "server", "signIn" => [ "tool-sign-in" ])
    expect(body["sync"]).to eq("inbound" => false, "pairing" => nil, "target" => nil,
                               "features" => %w[peer-channels images pairing])
  end

  it "tells a local engine, its sign-in by token file and its sync target" do
    allow(WarpEngine.config).to receive_messages(profile: :local, store_name: "Local",
                                                 sync_target: "https://games.example.org")

    expect(well_known).to include("name" => "Local", "profile" => "local", "signIn" => [ "token-file" ])
    expect(well_known["sync"]).to include("inbound" => false, "target" => "https://games.example.org")
  end

  it "names the Admin API only when it is on" do
    allow(WarpEngine::AdminApi.config).to receive(:enabled?).and_return(true)
    expect(well_known["adminApi"]).to eq(WarpEngine::AdminApi.url_path)

    allow(WarpEngine::AdminApi.config).to receive(:enabled?).and_return(false)
    expect(well_known["adminApi"]).to be_nil
  end

  it "tells whether the engine takes syncs and who may pair" do
    allow(WarpEngine::Sync.config.inbound).to receive(:enabled?).and_return(true)
    expect(well_known["sync"]).to include("inbound" => true, "pairing" => "admin")

    allow(WarpEngine::Sync.config.inbound).to receive(:pairing).and_return(:anyone)
    expect(well_known["sync"]["pairing"]).to eq("anyone")
  end
end
