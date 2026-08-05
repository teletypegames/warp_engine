require "rails_helper"
require "tmpdir"
require "digest"

RSpec.describe "POST /build/upload", type: :request do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret")
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def artifact(filename, content: "zipdata")
    path = File.join(Dir.mktmpdir, filename)
    File.write(path, content)
    Rack::Test::UploadedFile.new(path, "application/zip")
  end

  def upload(file:, name: "game", version: "1.0", headers: { "X-Update-Secret" => "s3cret" }, extra: {})
    post "/build/upload", headers: headers,
                          params: { name: name, version: version, file: file }.merge(extra)
  end

  it "rejects requests without a secret" do
    upload(file: artifact("game-1.0.html.zip"), headers: {})

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not accept the secret as a query param" do
    post "/build/upload", params: { secret: "s3cret", name: "game", version: "1.0",
                                    file: artifact("game-1.0.html.zip") }

    expect(response).to have_http_status(:unauthorized)
  end

  it "stores a valid artifact and returns its digest" do
    file = artifact("game-1.0.html.zip", content: "zipdata")
    upload(file: file)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["file"]).to eq("game-1.0.html.zip")
    expect(body["sha256"]).to eq(Digest::SHA256.hexdigest("zipdata"))
    expect(File.read(File.join(tmpdir, "game-1.0.html.zip"))).to eq("zipdata")
  end

  it "accepts binary target artifacts with the <name>-<version>- prefix" do
    upload(file: artifact("game-1.0-win-x64.zip"))

    expect(response).to have_http_status(:ok)
  end

  it "rejects a filename outside the <name>-<version> convention" do
    upload(file: artifact("other-2.0.html.zip"))

    expect(response).to have_http_status(:bad_request)
    expect(File.exist?(File.join(tmpdir, "other-2.0.html.zip"))).to be(false)
  end

  it "requires name and version" do
    post "/build/upload", headers: { "X-Update-Secret" => "s3cret" },
                          params: { file: artifact("game-1.0.html.zip") }

    expect(response).to have_http_status(:bad_request)
  end

  it "requires a file" do
    post "/build/upload", headers: { "X-Update-Secret" => "s3cret" },
                          params: { name: "game", version: "1.0" }

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a file over max_upload_size" do
    allow(WarpEngine.config).to receive(:max_upload_size).and_return(3)

    upload(file: artifact("game-1.0.html.zip", content: "toolarge"))

    expect(response).to have_http_status(:payload_too_large)
  end

  it "verifies a provided sha256 and rejects a mismatch" do
    upload(file: artifact("game-1.0.html.zip"), extra: { sha256: "0" * 64 })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(File.exist?(File.join(tmpdir, "game-1.0.html.zip"))).to be(false)
  end

  it "accepts a matching sha256" do
    upload(file: artifact("game-1.0.html.zip", content: "zipdata"),
           extra: { sha256: Digest::SHA256.hexdigest("zipdata") })

    expect(response).to have_http_status(:ok)
  end

  context "with application_token_source :database" do
    before do
      allow(WarpEngine.config).to receive(:application_token_source).and_return(:database)
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
    end

    it "accepts a token with the upload scope" do
      token = create(:application_token, scopes: [ "update", "upload" ])

      upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => token.plain_token })

      expect(response).to have_http_status(:ok)
      expect(token.reload.last_used_at).to be_present
    end

    it "rejects a token without the upload scope" do
      token = create(:application_token, scopes: [ "update" ])

      upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => token.plain_token })

      expect(response).to have_http_status(:unauthorized)
    end

    context "with enforce_software_ownership" do
      before { allow(WarpEngine.config).to receive(:enforce_software_ownership).and_return(true) }

      let(:token) { create(:application_token, scopes: [ "upload" ]) }

      it "allows uploading to the token owner's software" do
        create(:software, name: "game", owner: token.owner)

        upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:ok)
      end

      it "rejects uploading to another owner's software" do
        create(:software, name: "game", owner: create(:test_owner))

        upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:forbidden)
      end

      it "allows an unrestricted token regardless of owner" do
        create(:software, name: "game", owner: create(:test_owner))
        internal = create(:application_token, :unrestricted, scopes: [ "upload" ])

        upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => internal.plain_token })

        expect(response).to have_http_status(:ok)
      end

      it "allows uploading to an ownerless software" do
        create(:software, name: "game")

        upload(file: artifact("game-1.0.html.zip"), headers: { "X-Update-Secret" => token.plain_token })

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
