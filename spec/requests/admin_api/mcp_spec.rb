require "rails_helper"
require_relative "../../support/admin_api_helpers"

RSpec.describe "Admin API MCP server", type: :request do
  include AdminApiHelpers

  before { admin_config.mcp = true }

  def rpc(method, params = {}, id: 1, token: admin_token)
    message = { jsonrpc: "2.0", id: id, method: method, params: params }.compact
    post "/api/admin/v1/mcp", params: message.to_json,
                              headers: auth(token).merge("CONTENT_TYPE" => "application/json",
                                                         "ACCEPT" => "application/json, text/event-stream")
  end

  def tool_names(token: admin_token)
    rpc("tools/list", token: token)
    json.dig("result", "tools").map { |tool| tool["name"] }
  end

  it "does not exist while MCP is off" do
    admin_config.mcp = false

    rpc("tools/list")

    expect(response).to have_http_status(:not_found)
  end

  it "wants an admin token" do
    post "/api/admin/v1/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                              headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
  end

  it "answers initialize statelessly, naming itself" do
    rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "1" } })

    expect(response).to have_http_status(:ok)
    expect(json.dig("result", "serverInfo")).to include("name" => "warp_engine", "version" => WarpEngine::VERSION)
    expect(json.dig("result", "capabilities")).to have_key("tools")
    expect(response.headers["Mcp-Session-Id"]).to be_nil
  end

  it "accepts a notification with 202 and no body" do
    post "/api/admin/v1/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
                              headers: auth.merge("CONTENT_TYPE" => "application/json")

    expect(response).to have_http_status(:accepted)
    expect(response.body).to be_empty
  end

  it "lists a tool per operation the token may call, with hints" do
    rpc("tools/list")

    tools = json.dig("result", "tools").index_by { |tool| tool["name"] }
    expect(tools.keys).to include("software_list", "software_create", "download_summary", "admin_whoami")
    expect(tools["software_list"]["annotations"]).to include("readOnlyHint" => true, "destructiveHint" => false)
    expect(tools["software_delete"]["annotations"]).to include("readOnlyHint" => false, "destructiveHint" => true)
    expect(tools["software_update"]["inputSchema"]["required"]).to eq(%w[id])
  end

  it "leaves out uploads, the excluded resources and what the token may not do" do
    names = tool_names(token: admin_token_with(%w[admin:read admin:tokens]))

    expect(names).to include("software_list")
    expect(names).not_to include("software_create", "file_upload", "software_image_upload")
    expect(names.grep(/application_token|device_grant/)).to be_empty
  end

  it "lets the host put the tokens back in" do
    admin_config.mcp_exclude = []

    names = tool_names(token: admin_token_with(%w[admin:read admin:tokens]))

    expect(names).to include("application_token_list")
  end

  it "follows read-only and the resource list" do
    admin_config.read_only = true
    admin_config.resources = %i[softwares]

    expect(tool_names).to contain_exactly("software_list", "software_get", "admin_whoami")
  end

  it "calls a tool with the same answer the HTTP operation gives" do
    software = create(:software, name: "ra", title: "Blessing of Ra")

    rpc("tools/call", { name: "software_get", arguments: { id: software.id } })
    via_mcp = json.dig("result", "structuredContent")

    api_get "/softwares/#{software.id}"
    expect(via_mcp).to eq(json)
    expect(JSON.parse(response.body)).to eq(via_mcp)
  end

  it "writes through a tool and says so in the write event" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("warp_engine.admin_api.write") { |*, payload| events << payload }

    rpc("tools/call", { name: "platform_link_create",
                        arguments: { platform: "tic80", name: "TIC-80", url: "https://tic80.com" } })

    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(json.dig("result", "isError")).to be(false)
    expect(WarpEngine::PlatformLink.last.name).to eq("TIC-80")
    expect(events.first).to include(operation: "platform_links.create", via: :mcp)
  end

  it "reports a failed operation as a tool error with the HTTP status" do
    rpc("tools/call", { name: "software_get", arguments: { id: 999_999 } })

    result = json["result"]
    expect(result["isError"]).to be(true)
    expect(result["structuredContent"]).to eq("error" => "Not found", "status" => 404)
  end

  it "does not call a tool the token may not see" do
    rpc("tools/call", { name: "software_create", arguments: { name: "x", title: "X", platform: "tic80" } },
        token: admin_token_with("admin:read"))

    expect(json["error"]["code"]).to eq(-32_602)
    expect(json["error"].to_json).to include("Tool not found")
    expect(WarpEngine::Software.count).to eq(0)
  end

  it "answers a body that is not JSON with a parse error" do
    post "/api/admin/v1/mcp", params: "{nope", headers: auth.merge("CONTENT_TYPE" => "application/json")

    expect(response).to have_http_status(:bad_request)
    expect(json["error"]["code"]).to eq(-32_700)
  end

  it "does not open a stream" do
    get "/api/admin/v1/mcp", headers: auth

    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to eq("POST")
  end

  it "stops the host at boot when the mcp gem is missing" do
    allow(WarpEngine::AdminApi::Mcp).to receive(:available?).and_return(false)

    expect { WarpEngine::AdminApi::Mcp.ensure_available! }
      .to raise_error(WarpEngine::AdminApi::ConfigurationError, /gem "mcp"/)
  end
end
