require "rails_helper"
require "tmpdir"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API outlets", type: :request do
  include AdminApiHelpers

  let(:container) { Dir.mktmpdir }
  let(:assembly64) { { key: "assembly64", type: "assembly64", platforms: %w[c64], hosts: %w[a64.example.org] } }

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, outlets: [ assembly64 ])
    allow(WarpEngine::Outlets).to receive(:refresh)
    WarpEngine::SoftwareStatus.seed_defaults!
  end

  after { FileUtils.rm_rf(container) }

  def publish(name, platform: "c64")
    software = create(:software, name: name, title: name.titleize, platform: platform, status: "released")
    path = File.join(container, "#{name}.prg")
    File.binwrite(path, name)
    release = create(:release, software: software, version: "1.0")
    WarpEngine::ReleaseAsset.create!(release: release, kind: "cartridge", path: path)
    software
  end

  it "lists the catalog API first, then the configured outlets" do
    api_get "/outlets"

    expect(response).to have_http_status(:ok)
    expect(json["data"].map { |outlet| [ outlet["key"], outlet["type"], outlet["served"], outlet["materialized"] ] })
      .to eq([ [ "wecp", "wecp", true, false ], [ "assembly64", "assembly64", true, false ] ])
    expect(json["data"].last).to include("platforms" => %w[c64])
    expect(json["data"].last["details"]).to include("hosts" => %w[a64.example.org])
  end

  it "checks what one outlet offers and leaves out" do
    ariadne = publish("ariadne")
    create(:software, name: "empty", title: "Empty", platform: "c64", status: "released")

    api_get "/outlets/assembly64/check"

    expect(json["data"]).to include("key" => "assembly64", "offer" => true)
    expect(json["data"]["items"]).to eq([ { "softwareId" => ariadne.id, "name" => "ariadne", "title" => "Ariadne",
                                            "version" => "1.0", "kind" => "cartridge" } ])
    expect(json["data"]["skipped"].map { |skip| skip["name"] }).to eq(%w[empty])
  end

  it "has nothing to check on the catalog API, and no unknown outlet" do
    api_get "/outlets/wecp/check"
    expect(json["data"]).to include("offer" => false, "items" => [], "skipped" => [])

    api_get "/outlets/nope/check"
    expect(response).to have_http_status(:not_found)
  end

  it "answers 409 while the outlet configuration is invalid" do
    allow(WarpEngine.config).to receive(:outlets).and_return([ { key: "x", type: "gopher" } ])

    api_get "/outlets"

    expect(response).to have_http_status(:conflict)
  end
end
