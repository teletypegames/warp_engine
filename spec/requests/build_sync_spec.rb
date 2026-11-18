require "rails_helper"
require "tmpdir"
require_relative "../support/sync_helpers"

RSpec.describe "/build endpoints with a sync token", type: :request do
  include SyncHelpers
  include ActiveJob::TestHelper

  let(:tmpdir) { Dir.mktmpdir }
  let(:them) { WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false, inbound_enabled: true) }
  let(:sync_token) { them.issue_inbound_token! }
  let(:ci_token) { create(:application_token, scopes: %w[update upload]) }
  let(:software) { create(:software, name: "game", platform: "tic80", status: "released") }
  let(:release) { create(:release, software: software, version: "1.0") }

  before do
    allow(WarpEngine.config).to receive_messages(application_token_source: :database, application_token_owner_class: "TestOwner",
                                                 file_container_path: tmpdir)
    sync_config(inbound: { enabled: true })
    sync_peer(label: "Other", host: "https://other.example", secret: "other-token")
  end

  after { FileUtils.rm_rf(tmpdir) }

  def stub_publish
    definition = WarpEngine::Platform.new("tic80").definition
    platform = instance_double(WarpEngine::Platform, definition: definition)
    allow(platform).to receive(:publish) { release }
    allow(WarpEngine::Platform).to receive(:find!).and_call_original
    allow(WarpEngine::Platform).to receive(:find!).with("tic80").and_return(platform)
  end

  def publish(token, platform: "tic80", version: "1.0")
    post "/build/publish", headers: { "X-Update-Secret" => token.plain_token },
                           params: { name: "game", platform: platform, version: version }
  end

  def upload(token)
    path = File.join(tmpdir, "game-1.0.tic")
    File.write(path, "cart")
    post "/build/upload", headers: { "X-Update-Secret" => token.plain_token },
                          params: { name: "game", version: "1.0", file: Rack::Test::UploadedFile.new(path) }
  end

  it "uploads with the token of a peer that may push here" do
    upload(sync_token)

    expect(response).to have_http_status(:ok)
  end

  it "answers 400, not 401, to an accepted token without a file (the connection check)" do
    post "/build/upload", headers: { "X-Update-Secret" => sync_token.plain_token }

    expect(response).to have_http_status(:bad_request)
  end

  it "does not let a sync token install runtimes" do
    post "/build/runtime", headers: { "X-Update-Secret" => sync_token.plain_token }

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses with 403 while inbound sync is off, or the peer may not push" do
    token = sync_token
    sync_config(inbound: { enabled: false })
    upload(token)
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error"]).to eq("sync inbound is off here")

    sync_config(inbound: { enabled: true })
    them.update!(inbound_enabled: false)
    upload(token)
    expect(JSON.parse(response.body)["error"]).to include("from Them is off")
  end

  it "refuses what the inbound lists leave out, and logs it" do
    token = sync_token
    sync_config(inbound: { enabled: true, allowed_platforms: %w[c64], denied_softwares: %w[other-*] })

    upload(token)
    expect(response).to have_http_status(:ok)

    publish(token)
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error"]).to include("tic80 is not in allowed_platforms")
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "inbound", status: "skipped", http_status: 403, sync_peer_id: them.id)
  end

  it "publishes by sync with its origin, without pushing it on, and logs it as inbound" do
    stub_publish
    token = sync_token

    expect { publish(token) }.not_to have_enqueued_job(WarpEngine::SyncPushJob)
    expect(response).to have_http_status(:ok)
    expect(release.reload).to have_attributes(origin: "sync", sync_peer_id: them.id)

    event = WarpEngine::SyncEvent.last
    expect(event).to have_attributes(direction: "inbound", status: "succeeded", software_name: "game", software_id: software.id,
                                     version: "1.0", http_status: 200, token_prefix: token.token_prefix, sync_peer_id: them.id)
  end

  it "keeps a version the CI published here (protect_local), unless told otherwise" do
    token = sync_token
    release
    publish(token)
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)["error"]).to include("its own CI")

    stub_publish
    release.update_columns(origin: "sync")
    publish(token)
    expect(response).to have_http_status(:ok)

    release.update_columns(origin: "ci")
    sync_config(inbound: { enabled: true, protect_local: false })
    publish(token)
    expect(response).to have_http_status(:ok)
  end

  it "pushes a release the CI published to every outbound peer" do
    stub_publish

    expect { publish(ci_token) }.to have_enqueued_job(WarpEngine::SyncPushJob)
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "outbound", status: "queued", software_name: "game")
    expect(release.reload.origin).to eq("ci")
  end

  it "logs a refused inbound publish of an older version" do
    token = sync_token
    create(:release, software: software, version: "2.0", origin: "sync")

    publish(token)

    expect(response).to have_http_status(:conflict)
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "inbound", status: "skipped", http_status: 409)
  end
end
