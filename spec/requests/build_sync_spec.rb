require "rails_helper"
require "tmpdir"
require_relative "../support/sync_helpers"

RSpec.describe "/build endpoints with a sync token", type: :request do
  include SyncHelpers
  include ActiveJob::TestHelper

  let(:tmpdir) { Dir.mktmpdir }
  let(:sync_token) { create(:application_token, name: "from other", scopes: [ "sync" ]) }
  let(:ci_token) { create(:application_token, scopes: %w[update upload]) }
  let(:software) { create(:software, name: "game", platform: "tic80", status: "released") }
  let(:release) { create(:release, software: software, version: "1.0") }

  before do
    allow(WarpEngine.config).to receive_messages(application_token_source: :database, application_token_owner_class: "TestOwner",
                                                 file_container_path: tmpdir)
    sync_config
    WarpEngine::SyncServer.create!(label: "Other", host: "https://other.example", secret: "other-token")
  end

  after { FileUtils.rm_rf(tmpdir) }

  def stub_publish
    platform = instance_double(WarpEngine::Platform, publish: release)
    allow(WarpEngine::Platform).to receive(:find!).and_call_original
    allow(WarpEngine::Platform).to receive(:find!).with("tic80").and_return(platform)
  end

  def publish(token)
    post "/build/publish", headers: { "X-Update-Secret" => token.plain_token },
                           params: { name: "game", platform: "tic80", version: "1.0" }
  end

  it "uploads with the sync scope" do
    path = File.join(tmpdir, "game-1.0.tic")
    File.write(path, "cart")
    post "/build/upload", headers: { "X-Update-Secret" => sync_token.plain_token },
                          params: { name: "game", version: "1.0", file: Rack::Test::UploadedFile.new(path) }

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

  it "publishes by sync without pushing it on, and logs it as inbound" do
    stub_publish

    expect { publish(sync_token) }.not_to have_enqueued_job(WarpEngine::SyncPushJob)
    expect(response).to have_http_status(:ok)

    event = WarpEngine::SyncEvent.last
    expect(event).to have_attributes(direction: "inbound", status: "succeeded", software_name: "game",
                                     version: "1.0", http_status: 200, token_prefix: sync_token.token_prefix)
  end

  it "pushes a release the CI published to every active server" do
    stub_publish

    expect { publish(ci_token) }.to have_enqueued_job(WarpEngine::SyncPushJob)
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "outbound", status: "queued", software_name: "game")
  end

  it "logs a refused inbound publish" do
    create(:release, software: software, version: "2.0")

    publish(sync_token)

    expect(response).to have_http_status(:conflict)
    expect(WarpEngine::SyncEvent.last).to have_attributes(direction: "inbound", status: "skipped", http_status: 409)
  end
end
