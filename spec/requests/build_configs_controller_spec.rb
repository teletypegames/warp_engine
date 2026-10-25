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

  def woodpecker(platforms: nil, public_key: :default)
    WarpEngine::CI::Woodpecker::Adapter.new(
      url:        "https://ci.example.test",
      api_token:  "wp-token",
      platforms:  platforms.nil? ? ci_platforms : platforms,
      public_key: public_key == :default ? signing_key.public_to_pem : public_key
    )
  end

  def serving(adapter)
    allow(WarpEngine).to receive(:ci).and_return(adapter)
  end

  before { serving(woodpecker) }

  def signed_headers(body, path: "/build/config", digest_body: nil)
    digest = "sha-256=:#{Digest::SHA256.base64digest(digest_body || body)}:"
    inner = %{("@request-target" "content-digest");created=#{Time.now.to_i};alg="ed25519"}
    base = [
      %("@request-target": #{path}),
      %("content-digest": #{digest}),
      %("@signature-params": #{inner})
    ].join("\n")
    signature = Base64.strict_encode64(signing_key.sign(nil, base))
    {
      "Content-Digest" => digest,
      "Signature-Input" => "woodpecker-ci-extensions=#{inner}",
      "Signature" => "woodpecker-ci-extensions=:#{signature}:",
      "Content-Type" => "application/json"
    }
  end

  def cavage_signed_headers(method: "post", path: "/build/config")
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
      serving(woodpecker(platforms: {}))

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
      payload = extension_payload("platform: godot\n")
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:ok)
      configs = response.parsed_body["configs"]
      expect(configs.length).to eq(1)
      expect(configs.first["name"]).to eq("godot")
      pipeline = YAML.safe_load(configs.first["data"])
      expect(pipeline["steps"].map { |s| s["name"] }).to include("version", "publish")
      expect(configs.first["data"]).to include("mygame")
    end

    it "uses the marker's name override instead of the repo name" do
      payload = extension_payload("platform: godot\nname: othername\n")
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response.parsed_body["configs"].first["data"]).to include("othername")
      expect(response.parsed_body["configs"].first["data"]).not_to include("mygame")
    end

    it "accepts the configs key used by older Woodpecker payloads" do
      payload = { repo: { name: "mygame" },
                  configs: [ { name: ".woodpecker.yaml", data: "platform: godot\n" } ] }.to_json

      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:ok)
    end

    it "accepts a legacy draft-cavage signed request" do
      payload = extension_payload("platform: godot\n")
      post "/build/config", params: payload, headers: cavage_signed_headers

      expect(response).to have_http_status(:ok)
    end

    it "passes the marker's options to the pipeline and the repo's other configs through" do
      serving(woodpecker(platforms: { "dos" => { builder: "registry.example/dos-ci:1",
                                                 store: { image: "deploy:1", target: "deploy@host", known_host: "host key" } } }))
      payload = {
        repo: { name: "ttgwiki" },
        configuration: [
          { name: ".woodpecker/deploy.yaml", data: "steps:\n  - name: deploy\n    image: alpine\n" },
          { name: ".woodpecker/warp.yaml", data: "platform: dos\nstore_secret: store_ssh_key\n" }
        ]
      }.to_json

      post "/build/config", params: payload, headers: signed_headers(payload)

      configs = response.parsed_body["configs"]
      expect(configs.map { |config| config["name"] }).to eq([ "dos", ".woodpecker/deploy.yaml" ])
      expect(configs.first["data"]).to include("from_secret: store_ssh_key", "ttgwiki-$VERSION.zip")
      expect(configs.last["data"]).to eq("steps:\n  - name: deploy\n    image: alpine\n")
    end

    it "previews a pipeline with options" do
      serving(woodpecker(platforms: { "dos" => { builder: "b", store: { image: "i", target: "t", known_host: "k" } } }))

      get "/build/config", params: { platform: "dos", name: "ttgwiki", options: { store_secret: "store_ssh_key" } }

      expect(response.body).to include("from_secret: store_ssh_key")
    end

    it "returns 204 for a non-marker config" do
      payload = extension_payload("steps:\n  - name: build\n    image: alpine\n")
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 when no configuration is sent" do
      payload = { repo: { name: "mygame" } }.to_json
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 422 for a marker with an unknown platform" do
      payload = extension_payload("platform: amiga\n")
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a request with an invalid signature" do
      payload = extension_payload("platform: godot\n")
      headers = signed_headers(payload)
      other_key = OpenSSL::PKey.generate_key("ed25519")
      serving(woodpecker(public_key: other_key.public_to_pem))

      post "/build/config", params: payload, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a request whose body does not match the signed content-digest" do
      payload = extension_payload("platform: godot\n")
      tampered = signed_headers(payload, digest_body: "something else")

      post "/build/config", params: payload, headers: tampered

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a request without a signature header" do
      post "/build/config", params: extension_payload("platform: godot\n"),
                            headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects every request when no public key is configured" do
      serving(woodpecker(public_key: nil))

      payload = extension_payload("platform: godot\n")
      post "/build/config", params: payload, headers: signed_headers(payload)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "shipped templates" do
    it "renders every template to valid YAML with non-empty steps" do
      templates = Dir[WarpEngine::CI::Woodpecker::PipelineConfig.templates_dir.join("*/pipeline.yaml.erb")]
      expect(templates).not_to be_empty

      templates.each do |path|
        platform = File.basename(File.dirname(path))
        config = WarpEngine::CI::Woodpecker::PipelineConfig.new(
          platforms: { platform => { builder: "registry.example/builder:1",
                                     exporter: "registry.example/exporter:1" } }
        )

        yaml = config.render(
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

    it "pulls the :latest builder and player images on every c64 and plus4 run" do
      %w[c64 plus4].each do |platform|
        config = WarpEngine::CI::Woodpecker::PipelineConfig.new(
          platforms: { platform => { builder: "registry.example/builder:latest",
                                     exporter: "registry.example/player:latest" } }
        )
        yaml = config.render(platform: platform, name: "example", update_server: "https://games.example")
        steps = YAML.safe_load(yaml)["steps"].index_by { |step| step["name"] }

        expect(steps.fetch("build")["pull"]).to be(true), "#{platform}/build: not pulled"
        expect(steps.fetch("package")["pull"]).to be(true), "#{platform}/package: not pulled"
      end
    end
  end
end
