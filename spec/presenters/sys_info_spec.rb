require "rails_helper"

RSpec.describe WarpEngine::SysInfo do
  def section(title) = described_class.new.sections.find { |candidate| candidate.title == title }

  def value(title, label) = section(title).rows.to_h.fetch(label)

  it "describes every part of the configuration" do
    expect(described_class.new.sections.map(&:title))
      .to eq([ "Engine", "Publishing", "Storage, images and access", "Client sign-in", "CI", "Platforms", "Outlets",
               "Admin API", "Additional resources" ])
  end

  it "says whether a secret is set, never what it is" do
    allow(WarpEngine.config).to receive(:update_secret).and_return("s3cret-value")

    expect(value("Publishing", "Shared secret (UPDATE_SECRET)")).to eq("set")
    expect(described_class.new.sections.flat_map(&:rows).flatten.join(" ")).not_to include("s3cret-value")
  end

  it "lists every platform with its kinds" do
    rows = section("Platforms").tables.first.rows

    expect(rows.map(&:first)).to eq(WarpEngine::Platform.names)
    expect(rows.find { |row| row.first == "c64" }).to include("C64", "built-in", "cartridge")
  end

  it "describes the CI server without its token" do
    adapter = WarpEngine::CI::Woodpecker::Adapter.new(url: "https://ci.example", api_token: "tok-123", repo_owner: "games",
                                                      platforms: { "godot" => { builder: "registry.example/godot:4" } })
    allow(WarpEngine).to receive(:ci).and_return(adapter)

    ci = section("CI")
    expect(ci.intro).to eq("Woodpecker, connected.")
    expect(ci.rows.to_h).to include("Server" => "https://ci.example", "API token" => "set")
    expect(ci.tables.first.rows.first.first(2)).to eq([ "godot", "registry.example/godot:4" ])
    expect(ci.rows.flatten.join(" ")).not_to include("tok-123")
  end

  it "says when the CI is off and sign-in is not configured" do
    allow(WarpEngine).to receive(:ci).and_return(WarpEngine::CI::Null.new)
    allow(WarpEngine.config).to receive(:access_token_owner_class).and_return(nil)

    expect(section("CI").intro).to start_with("Off")
    expect(section("Client sign-in").intro).to start_with("Off")
  end

  it "reports an invalid outlet configuration instead of failing" do
    allow(WarpEngine::Outlets).to receive(:validate!).and_raise(WarpEngine::ConfigurationError, "two outlets share the key x")

    expect(section("Outlets").intro).to include("INVALID", "two outlets share the key x")
  end
end
