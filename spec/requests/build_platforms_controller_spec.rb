require "rails_helper"

RSpec.describe "Build platforms endpoint", type: :request do
  let(:adapter) do
    WarpEngine::CI::Woodpecker::Adapter.new(url: "https://ci.example.test", api_token: "wp-token",
                                            platforms: { "c64" => { builder: "registry.example/c64-builder:1" } })
  end

  before { allow(WarpEngine).to receive(:ci).and_return(adapter) }

  it "describes every platform in registry order" do
    get "/build/platforms"

    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body)["platforms"].map { |platform| platform["name"] }
    expect(names).to eq(WarpEngine::Platform.names)
  end

  it "describes a platform's kinds, metadata, web runtimes, marker and builder" do
    get "/build/platforms/c64"

    json = JSON.parse(response.body)
    expect(json).to include("name" => "c64", "label" => "C64", "releaseRule" => nil, "tooling" => {})
    expect(json["kinds"].first).to include("name" => "cartridge", "upload" => "NAME-VERSION.prg", "required" => true)
    expect(json["metadata"]).to include("format" => "json", "file" => "metadata.json")
    expect(json["version"]).to eq("source" => "metadata", "command" => nil)
    expect(json["web"].first).to include("key" => "emulatorjs", "runtime" => "emulatorjs", "default" => true)
    expect(json["ci"]).to eq("adapter" => "Woodpecker", "served" => true, "builder" => "registry.example/c64-builder:1",
                             "marker" => { "file" => ".woodpecker.yaml", "content" => "platform: c64\n" })
  end

  it "tells a platform whose version comes from a command and whose metadata is Lua" do
    get "/build/platforms/tic80"

    json = JSON.parse(response.body)
    expect(json["metadata"]).to include("format" => "lua", "file" => nil)
    expect(json["version"]["source"]).to eq("command")
    expect(json["ci"]).to include("served" => false, "builder" => nil)
  end

  it "passes the host's tooling through" do
    config = WarpEngine::Configuration.new
    config.platform_tooling :c64, template: "https://git.example/build/c64-tools"
    config.platform_tooling :c64, demo: "https://git.example/demos/c64-demo"
    allow(WarpEngine).to receive(:config).and_return(config)

    get "/build/platforms/c64"

    expect(JSON.parse(response.body)["tooling"]).to eq("template" => "https://git.example/build/c64-tools",
                                                       "demo" => "https://git.example/demos/c64-demo")
  end

  it "answers 404 for an unknown platform" do
    get "/build/platforms/amiga"

    expect(response).to have_http_status(:not_found)
  end

  describe "metadata schema" do
    it "serves the JSON Schema with the publish keys, the version and the web section" do
      WarpEngine::SoftwareCategory.create!(key: "puzzle", label: "Puzzle", position: 1)

      get "/build/platforms/c64/metadata-schema"

      expect(response.media_type).to eq("application/schema+json")
      schema = JSON.parse(response.body)
      expect(schema["required"]).to eq(%w[name title version])
      expect(schema["properties"].keys).to include(*WarpEngine::Publish::MetadataReader::KEYS.map(&:to_s), "version")
      expect(schema["properties"]["category"]["examples"]).to eq(%w[puzzle])
      expect(schema["properties"]["shelf_name"]).to include("maxLength" => 32)
      web = schema["properties"]["web"]["properties"]
      expect(web["runtime"]["enum"]).to eq(%w[emulatorjs])
      expect(web["params"]["properties"]).to include("core" => { "type" => "string" }, "options" => { "type" => "object" })
    end

    it "leaves the version out where a command reads it" do
      get "/build/platforms/tic80/metadata-schema"

      schema = JSON.parse(response.body)
      expect(schema["required"]).to eq(%w[name title])
      expect(schema["properties"]).not_to have_key("version")
    end

    it "answers 404 for an unknown platform" do
      get "/build/platforms/amiga/metadata-schema"

      expect(response).to have_http_status(:not_found)
    end
  end
end
