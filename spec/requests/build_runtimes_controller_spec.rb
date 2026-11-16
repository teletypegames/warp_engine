require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe "POST /build/runtime", type: :request do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def send_runtime(files, version: "1.1", headers: { "X-Update-Secret" => "s3cret" })
    post "/build/runtime", headers: headers,
                           params: { name: "tic80", version: version, file: Rack::Test::UploadedFile.new(runtime_zip(files), "application/zip") }
  end

  it "installs a version (201), takes it again (200) and refuses other files for it (409)" do
    send_runtime({ "tic80.js" => "js", "tic80.wasm" => "wasm" })
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("name" => "tic80", "version" => "1.1")

    send_runtime({ "tic80.js" => "js", "tic80.wasm" => "wasm" })
    expect(response).to have_http_status(:ok)

    send_runtime({ "tic80.js" => "other", "tic80.wasm" => "wasm" })
    expect(response).to have_http_status(:conflict)
  end

  it "refuses a caller without the secret and an incomplete zip" do
    send_runtime({ "tic80.js" => "js" }, headers: {})
    expect(response).to have_http_status(:unauthorized)

    send_runtime({ "tic80.js" => "js" })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/lacks tic80.wasm/)
  end
end
