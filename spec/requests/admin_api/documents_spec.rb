require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API OpenAPI document", type: :request do
  include AdminApiHelpers

  it "wants an admin:read token by default" do
    get "/api/admin/v1/openapi.json"
    expect(response).to have_http_status(:unauthorized)

    get "/api/admin/v1/openapi.json", headers: auth(admin_token_with("admin:tokens"))
    expect(response).to have_http_status(:forbidden)
  end

  it "is a valid OpenAPI 3.1 document addressed to this host" do
    get "/api/admin/v1/openapi.json", headers: auth

    expect(response).to have_http_status(:ok)
    expect(json["openapi"]).to eq("3.1.0")
    expect(json["info"]).to include("version" => WarpEngine::VERSION, "x-api-version" => 1)
    expect(json["servers"]).to eq([ { "url" => "http://www.example.com/api/admin/v1" } ])
    expect(JSONSchemer.openapi(json).validate.map { |e| e["error"] }).to be_empty
  end

  it "can be public, and comes as YAML too" do
    admin_config.openapi_requires_auth = false

    get "/api/admin/v1/openapi.yaml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/yaml")
    expect(YAML.safe_load(response.body)["openapi"]).to eq("3.1.0")
  end

  it "describes only what this host serves" do
    admin_config.read_only = true
    admin_config.resources = %i[softwares downloads]

    get "/api/admin/v1/openapi.json", headers: auth

    verbs = json["paths"].values.flat_map(&:keys).uniq
    expect(verbs).to eq(%w[get])
    expect(json["paths"].keys).to include("/softwares", "/downloads/summary", "/me")
    expect(json["paths"].keys).not_to include("/files", "/platform_links", "/pipelines")
  end

  it "leaves out what the host has not configured" do
    get "/api/admin/v1/openapi.json", headers: auth

    expect(json["paths"].keys).not_to include("/pipelines", "/device_grants", "/softwares/{softwareId}/extras/{association}")
  end

  it "names the scope every operation needs" do
    get "/api/admin/v1/openapi.json", headers: auth

    operation = json.dig("paths", "/application_tokens", "post")
    expect(operation["x-required-scope"]).to eq("admin:tokens")
    expect(json.dig("paths", "/softwares", "get", "x-required-scope")).to eq("admin:read")
    expect(json.dig("paths", "/me", "get")).not_to have_key("x-required-scope")
  end

  it "has an operation for every route and a route for every operation" do
    ci = instance_double(WarpEngine::CI::Woodpecker::Adapter, configured?: true, name: "Woodpecker")
    allow(WarpEngine).to receive(:ci).and_return(ci)
    allow(WarpEngine.config).to receive(:access_token_owner_class).and_return("TestOwner")
    allow(WarpEngine::AdditionalResource).to receive(:api_for).and_return([ double(association: :notes) ])

    document = openapi_document
    documented = document["paths"].flat_map { |path, verbs| verbs.keys.map { |verb| "#{verb.upcase} #{path}" } }
    routed = WarpEngine::Engine.routes.routes.select { |route| route.defaults[:controller] == "warp_engine/api/admin/operations" }
                                    .map do |route|
      "#{route.verb} #{route.path.spec.to_s.delete_prefix('/api/admin/v1').gsub(/:(\w+)/, '{\1}')}"
    end

    expect(documented).to match_array(routed)
    expect(documented.size).to eq(WarpEngine::AdminApi::Registry.operations.size)
  end

  it "gives every operation a unique id, which is also its MCP tool name" do
    names = WarpEngine::AdminApi::Registry.operations.map(&:tool_name)

    expect(names).to eq(names.uniq)
    expect(names).to all(match(/\A[a-z_]{1,64}\z/))
  end

  describe "the docs page" do
    it "does not exist unless the host asks for it" do
      get "/api/admin/v1/docs", headers: auth

      expect(response).to have_http_status(:not_found)
    end

    it "renders the document with Redoc" do
      admin_config.docs_ui = true
      admin_config.openapi_requires_auth = false

      get "/api/admin/v1/docs"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("redoc.standalone.js", "WarpEngine Admin API")
    end
  end

  describe "the service descriptor" do
    it "says nothing of the Admin API while it is off" do
      admin_config.enabled = false

      get "/api/service"

      expect(json["admin"]).to be_nil
    end

    it "names the Admin API's addresses once it is on" do
      admin_config.mcp = true

      get "/api/service"

      expect(json["admin"]).to eq(
        "version"    => 1,
        "url"        => "http://www.example.com/api/admin/v1",
        "openapiUrl" => "http://www.example.com/api/admin/v1/openapi.json",
        "mcpUrl"     => "http://www.example.com/api/admin/v1/mcp",
        "schemes"    => [ "bearer" ]
      )
    end

    it "has no MCP address while MCP is off" do
      get "/api/service"

      expect(json["admin"]["mcpUrl"]).to be_nil
    end
  end
end
