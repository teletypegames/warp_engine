require "rails_helper"
require "tmpdir"
require "digest"
require_relative "../support/sync_helpers"

RSpec.describe "/build/images", type: :request do
  include SyncHelpers

  let(:tmpdir) { Dir.mktmpdir }
  let(:them) { WarpEngine::SyncPeer.create!(label: "Them", outbound_enabled: false, inbound_enabled: true) }
  let(:sync_token) { them.issue_inbound_token! }
  let(:software) { create(:software, name: "game", platform: "tic80", status: "released") }

  before do
    allow(WarpEngine.config).to receive_messages(application_token_source: :database, application_token_owner_class: "TestOwner")
    sync_config(inbound: { enabled: true })
    create(:release, software: software, version: "1.0")
  end

  after { FileUtils.rm_rf(tmpdir) }

  def image_file(name, body)
    path = File.join(tmpdir, name)
    File.binwrite(path, body)
    path
  end

  def manifest(*entries, token: sync_token)
    post "/build/images", params: { name: "game", images: entries }.to_json,
                          headers: { "X-Update-Secret" => token.plain_token, "CONTENT_TYPE" => "application/json" }
    JSON.parse(response.body)
  end

  def upload(path, token: sync_token, sha: Digest::SHA256.file(path).hexdigest)
    post "/build/images/upload", headers: { "X-Update-Secret" => token.plain_token },
                                 params: { name: "game", sha256: sha, file: Rack::Test::UploadedFile.new(path, "image/png") }
  end

  def entry(path, default: false)
    { sha256: Digest::SHA256.file(path).hexdigest, filename: File.basename(path), contentType: "image/png", default: default }
  end

  it "names the images it lacks, takes them, then follows the manifest's order and default" do
    one = image_file("one.png", "first")
    two = image_file("two.png", "second")

    expect(manifest(entry(one), entry(two, default: true))).to eq("applied" => false, "missing" => [ entry(one)[:sha256], entry(two)[:sha256] ])

    upload(two)
    upload(one)
    expect(response).to have_http_status(:ok)

    expect(manifest(entry(one), entry(two, default: true))).to eq("applied" => true, "missing" => [])
    gallery = software.software_images.ordered.to_a
    expect(gallery.map(&:sha256)).to eq([ entry(one)[:sha256], entry(two)[:sha256] ])
    expect(gallery.map(&:is_default)).to eq([ false, true ])
    expect(gallery.map(&:origin).uniq).to eq([ "sync" ])
  end

  it "keeps an image it has by digest and unlinks what the manifest dropped" do
    one = image_file("one.png", "first")
    two = image_file("two.png", "second")
    [ one, two ].each { |path| upload(path) }

    manifest(entry(two))

    expect(software.software_images.reload.map(&:sha256)).to eq([ entry(two)[:sha256] ])
  end

  it "refuses an upload whose digest is not the one sent" do
    upload(image_file("one.png", "first"), sha: "0" * 64)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "answers 409 for a software it does not have" do
    post "/build/images", params: { name: "elsewhere", images: [] }.to_json,
                          headers: { "X-Update-Secret" => sync_token.plain_token, "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:conflict)
  end

  it "keeps images set here by hand under protect_local" do
    WarpEngine::SoftwareImage.create!(software: software, image: create(:image), origin: "local")

    manifest

    expect(response).to have_http_status(:conflict)
    expect(software.software_images.count).to eq(1)
  end

  it "answers 403 when the inbound lists keep the software out" do
    sync_config(inbound: { enabled: true, denied_softwares: %w[game] })

    manifest

    expect(response).to have_http_status(:forbidden)
  end

  it "answers 401 without a credential that may publish" do
    reader = create(:application_token, scopes: %w[catalog])
    manifest(token: reader)

    expect(response).to have_http_status(:unauthorized)
  end
end
