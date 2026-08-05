require "rails_helper"

RSpec.describe "Build configs endpoint", type: :request do
  let(:signing_key) { OpenSSL::PKey.generate_key("ed25519") }
  let(:ci_platforms) do
    {
      "godot" => { builder: "registry.example/godot-builder:4.6" },
      "tic80" => { builder: "registry.example/tic80-builder:1.0",
                   exporter: "registry.example/tic80pro:1.0" }
    }
  end

  before do
    allow(WarpEngine.config).to receive(:ci_platforms).and_return(ci_platforms)
    allow(WarpEngine.config).to receive(:ci_extension_public_key).and_return(signing_key.public_to_pem)
  end

  def signed_headers(method: "post", path: "/build/config")
    date = Time.now.httpdate
    signing_string = "(request-target): #{method} #{path}\ndate: #{date}"
    signature = Base64.strict_encode64(signing_key.sign(nil, signing_string))
    {
      "Date" => date,
      "Signature" => %(keyId="woodpecker-ci-plugins",algorithm="ed25519",headers="(request-target) date",signature="#{signature}"),
      "Content-Type" => "application/json"
    }
  end

  def extension_payload(marker_yaml, repo_name: "mygame")
    {
      repo: { name: repo_name },
      pipeline: { branch: "master" },
      configuration: [ { name: ".woodpecker.yaml", data: marker_yaml } ]
    }.to_json
  end

  describe "GET /build/config" do
    it "renders the pipeline for a configured platform" do
      get "/build/config", params: { platform: "godot", name: "mygame" }

      expect(response).to have_http_status(:ok)
      pipeline = YAML.safe_load(response.body)
      expect(pipeline["steps"]).to be_present
      expect(response.body).to include("registry.example/godot-builder:4.6")
      expect(response.body).to include("mygame")
    end

    it "returns 404 for an unknown platform" do
      get "/build/config", params: { platform: "nope" }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the feature is not configured" do
      allow(WarpEngine.config).to receive(:ci_platforms).and_return({})

      get "/build/config", params: { platform: "godot" }

      expect(response).to have_http_status(:not_found)
    end

    it "rejects path traversal in the platform param" do
      get "/build/config", params: { platform: "../secrets" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /build/config" do
    it "returns the rendered pipeline for a marker config" do
      post "/build/config", params: extension_payload("platform: godot\n"),
                            headers: signed_headers

      expect(response).to have_http_status(:ok)
      configs = response.parsed_body["configs"]
      expect(configs.length).to eq(1)
      expect(configs.first["name"]).to eq("godot")
      pipeline = YAML.safe_load(configs.first["data"])
      expect(pipeline["steps"].map { |s| s["name"] }).to include("version", "publish")
      expect(configs.first["data"]).to include("mygame")
    end

    it "uses the marker's name override instead of the repo name" do
      post "/build/config", params: extension_payload("platform: godot\nname: othername\n"),
                            headers: signed_headers

      expect(response.parsed_body["configs"].first["data"]).to include("othername")
      expect(response.parsed_body["configs"].first["data"]).not_to include("mygame")
    end

    it "accepts the configs key used by older Woodpecker payloads" do
      payload = { repo: { name: "mygame" },
                  configs: [ { name: ".woodpecker.yaml", data: "platform: godot\n" } ] }.to_json

      post "/build/config", params: payload, headers: signed_headers

      expect(response).to have_http_status(:ok)
    end

    it "returns 204 for a non-marker config" do
      full_pipeline = "steps:\n  - name: build\n    image: alpine\n"

      post "/build/config", params: extension_payload(full_pipeline),
                            headers: signed_headers

      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 when no configuration is sent" do
      post "/build/config", params: { repo: { name: "mygame" } }.to_json,
                            headers: signed_headers

      expect(response).to have_http_status(:no_content)
    end

    it "returns 422 for a marker with an unknown platform" do
      post "/build/config", params: extension_payload("platform: amiga\n"),
                            headers: signed_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a request with an invalid signature" do
      headers = signed_headers
      other_key = OpenSSL::PKey.generate_key("ed25519")
      allow(WarpEngine.config).to receive(:ci_extension_public_key).and_return(other_key.public_to_pem)

      post "/build/config", params: extension_payload("platform: godot\n"), headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a request without a signature header" do
      post "/build/config", params: extension_payload("platform: godot\n"),
                            headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects every request when no public key is configured" do
      allow(WarpEngine.config).to receive(:ci_extension_public_key).and_return(nil)
      allow(WarpEngine.config).to receive(:ci_extension_public_key_url).and_return(nil)

      post "/build/config", params: extension_payload("platform: godot\n"),
                            headers: signed_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "shipped templates" do
    it "renders every template to valid YAML with non-empty steps" do
      templates = Dir[WarpEngine::Engine.root.join("lib/warp_engine/ci_templates/*.yaml.erb")]
      expect(templates).not_to be_empty

      templates.each do |path|
        platform = File.basename(path, ".yaml.erb")
        allow(WarpEngine.config).to receive(:ci_platforms).and_return(
          platform => { builder: "registry.example/builder:1", exporter: "registry.example/exporter:1" }
        )

        yaml = WarpEngine::CiConfigService.new.render(
          platform: platform, name: "example", update_server: "https://games.example"
        )

        expect(yaml).to be_present, "#{platform}: no template rendered"
        pipeline = YAML.safe_load(yaml)
        expect(pipeline["steps"]).to be_present, "#{platform}: no steps"
        pipeline["steps"].each do |step|
          expect(step["image"]).to be_present, "#{platform}/#{step['name']}: missing image"
          expect(step["commands"]).to be_present, "#{platform}/#{step['name']}: missing commands"
        end
      end
    end
  end
end
