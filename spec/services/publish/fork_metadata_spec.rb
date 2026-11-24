require "rails_helper"

RSpec.describe "publishing the source and the parent of a fork" do
  let(:recorder) { WarpEngine::Publish::Recorder.new(WarpEngine::Platform.find!("c64").definition) }

  before { WarpEngine::SoftwareStatus.seed_defaults! }

  it "spreads a nested fork_of into the flat keys, a flat key winning" do
    metadata = WarpEngine::Publish::MetadataReader.flatten_fork_of(
      { name: "mine", fork_of: { "engine" => "https://games.example", "name" => "parent", "version" => "1.0.0" }, fork_of_version: "1.1.0" }
    )

    expect(metadata).to include(fork_of_engine: "https://games.example", fork_of_name: "parent", fork_of_version: "1.1.0")
  end

  it "keeps the fork keys a Lua header gives" do
    upload = Struct.new(:versioned) { def path(name) = File.join(Dir.tmpdir, name) }.new("mine-1.0.0")
    File.write(upload.path("mine-1.0.0.lua"), "-- name: mine\n-- fork_of_engine: https://games.example\n-- fork_of_name: parent\nprint()\n")

    metadata = WarpEngine::Publish::MetadataReader.read(:lua, upload)

    expect(metadata).to include(name: "mine", fork_of_engine: "https://games.example", fork_of_name: "parent")
  end

  it "lays a metadata.json over the Lua header, for the keys a header cannot hold" do
    upload = Struct.new(:versioned) { def path(name) = File.join(Dir.tmpdir, name) }.new("both-1.0.0")
    File.write(upload.path("both-1.0.0.lua"), "-- name: both\n-- title: From the header\nprint()\n")
    File.write(upload.path("both-1.0.0.metadata.json"), %({"title": "From the JSON", "web": {"enabled": false}}))

    metadata = WarpEngine::Publish::MetadataReader.read(:lua, upload)

    expect(metadata).to include(name: "both", title: "From the JSON", web: { enabled: false })
  ensure
    File.delete(upload.path("both-1.0.0.metadata.json"))
  end

  it "makes the repo the source link and records the parent" do
    release = recorder.record({ name: "mine", title: "Mine", repo: "https://git.example/mine.git", forks_allowed: "false",
                                fork_of_engine: "https://games.example/", fork_of_name: "parent" }, "1.0.0", { "cartridge" => "mine-1.0.0.prg" })
    software = release.software.reload

    expect(software.source_link).to have_attributes(url: "https://git.example/mine.git", kind: "source", label: "Repository")
    expect(software).to have_attributes(forks_allowed: false, fork_of_engine: "https://games.example", fork_of_name: "parent")
  end

  it "moves the source to a new repo instead of adding a second one" do
    recorder.record({ name: "mine", title: "Mine", repo: "https://git.example/old.git" }, "1.0.0", { "cartridge" => "mine-1.0.0.prg" })
    release = recorder.record({ name: "mine", title: "Mine", repo: "https://git.example/new.git" }, "1.1.0", { "cartridge" => "mine-1.1.0.prg" })

    sources = WarpEngine::ExternalLink.kept.sources.where(software_id: release.software_id)
    expect(sources.pluck(:url)).to eq([ "https://git.example/new.git" ])
  end
end
