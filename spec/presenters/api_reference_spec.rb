require "rails_helper"

RSpec.describe WarpEngine::ApiReference do
  let(:reference) { described_class.new(WarpEngine::AdminApi::OpenApi.document(server_url: "https://games.example/api/admin/v1")) }

  before do
    allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
    WarpEngine.config.admin_api = WarpEngine::AdminApi::Configuration.new.tap { |c| c.enabled = true }
  end

  after { WarpEngine.config.admin_api = nil }

  def operation(verb, path)
    reference.groups.flat_map(&:operations).find { |op| op.verb == verb && op.path == path }
  end

  it "reads the title, base URL and every operation into groups" do
    expect(reference.title).to eq("WarpEngine Admin API")
    expect(reference.server_url).to eq("https://games.example/api/admin/v1")
    expect(reference.groups.map(&:name)).to include("Softwares", "Sync servers")
    expect(reference.operation_count).to eq(WarpEngine::AdminApi::OpenApi.document(server_url: "x")[:paths].values.sum(&:size))
  end

  it "lists the parameters with their place, type and notes" do
    list = operation("get", "/sync_events")
    direction = list.parameters.find { |field| field.name == "direction" }

    expect(direction).to have_attributes(location: "query", type: "string", notes: [ "one of: outbound, inbound" ])
    expect(operation("get", "/sync_servers/{id}").parameters.first).to have_attributes(name: "id", location: "path", required: true)
  end

  it "reads the request body and the success response, linking the schemas" do
    push = operation("post", "/sync_servers/{id}/push")

    expect(push.body.map(&:name)).to include("all", "filtered", "channels", "skipExisting", "dryRun")
    expect(push.body.find { |field| field.name == "channels" }.notes).to include(a_string_starting_with("items one of: stable"))
    expect(push.responses.find(&:success?).fields.first).to have_attributes(name: "data", type: "SyncPush", ref: "SyncPush")
    expect(push.responses.reject(&:success?).map(&:status)).to include("400", "401", "403")
    expect(push.responses.reject(&:success?).first.ref).to eq("Error")
    expect(push.scope).to eq("admin:write")
    expect(push.curl).to start_with(%(curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}'))
    expect(operation("post", "/sync_servers").curl).to include(%(-d '{"label":"...","host":"...","secret":"..."}'))
    expect(push.curl).to end_with(%("https://games.example/api/admin/v1/sync_servers/{id}/push"))
  end

  it "flattens inline objects and marks nullable fields in the schemas" do
    sync_push = reference.schemas.find { |schema| schema.name == "SyncPush" }
    server = reference.schemas.find { |schema| schema.name == "SyncServer" }

    expect(sync_push.fields.map(&:name)).to include("releases", "releases[].software", "releases[].version")
    expect(server.fields.find { |field| field.name == "lastSyncedAt" }).to have_attributes(type: "datetime", nullable: true)
    expect(sync_push.anchor).to eq("we-ar-schema-syncpush")
  end
end
