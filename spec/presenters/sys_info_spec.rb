require "rails_helper"
require "tmpdir"

RSpec.describe WarpEngine::SysInfo do
  let(:info) { described_class.new(live: false) }

  def group(key, from: info) = from.tree.find { |candidate| candidate.key == key }

  def find(key, nodes = info.tree)
    nodes.each do |candidate|
      return candidate if candidate.key == key

      found = find(key, candidate.children)
      return found if found
    end
    nil
  end

  def woodpecker
    WarpEngine::CI::Woodpecker::Adapter.new(url: "https://ci.example", api_token: "tok-123", repo_owner: "games",
                                            platforms: { "godot" => { builder: "registry.example/godot:4" } })
  end

  it "describes every part of the configuration as a group with an icon" do
    expect(info.tree.map(&:key)).to eq(%w[engine publishing adapters signin ci platforms runtimes outlets adminapi extras])
    expect(info.tree.map(&:icon)).to all(be_a(Symbol))
  end

  it "gives a branch the worst status below it and counts the leaves" do
    node = described_class::Node.new(key: "x", label: "x", children: [
      described_class::Node.new(key: "a", label: "a", status: "ok"),
      described_class::Node.new(key: "b", label: "b", status: "warn", children: [
        described_class::Node.new(key: "c", label: "c", status: "error")
      ])
    ])

    expect(node.rolled_status).to eq("error")
    expect(node).to be_problem
    expect(node.tally).to eq("2 settings · 1 to look at")
    expect(info.counts.keys).to eq(described_class::STATUSES)
  end

  it "says whether a secret is set, never what it is" do
    allow(WarpEngine.config).to receive_messages(update_secret: "s3cret-value", application_token_source: :env)

    expect(find("publishing.secret")).to have_attributes(value: "set", status: "ok")
    expect(info.tree.flat_map(&:leaves).flat_map { |leaf| [ leaf.value, *leaf.chips, leaf.hint ] }.join(" ")).not_to include("s3cret-value")
  end

  it "calls a missing shared secret an error" do
    allow(WarpEngine.config).to receive_messages(update_secret: nil, application_token_source: :env)

    expect(find("publishing.secret").status).to eq("error")
    expect(group("publishing").rolled_status).to eq("error")
  end

  it "flags a file container the engine cannot write into" do
    allow(WarpEngine.config).to receive(:file_container_path).and_return("/does/not/exist")

    expect(find("engine.container")).to have_attributes(status: "error", chips: [ "missing" ])
  end

  it "lists every platform with its kinds" do
    platforms = group("platforms").children

    expect(platforms.map { |node| node.label.split(" · ").first }).to eq(WarpEngine::Platform.names)
    expect(find("platforms.c64.accepts").chips).to include("cartridge")
  end

  it "describes the CI server without its token and leaves the live check off when asked" do
    allow(WarpEngine).to receive(:ci).and_return(woodpecker)

    expect(group("ci").label).to eq("CI · Woodpecker")
    expect(find("ci.platform.godot").value).to eq("registry.example/godot:4")
    expect(find("ci.live")).to have_attributes(value: "off", status: "off")
    expect(group("ci").leaves.flat_map { |leaf| [ leaf.value, *leaf.chips ] }.join(" ")).not_to include("tok-123")
  end

  it "runs the live check and reports a refused token as an error" do
    adapter = woodpecker
    allow(WarpEngine).to receive(:ci).and_return(adapter)
    allow(adapter).to receive(:ping).and_return(WarpEngine::CI::Ping.new(ok: false, detail: "Woodpecker API error 401", ms: 84))

    live = described_class.new(live: true)

    expect(live).to be_live
    expect(find("ci.live", live.tree)).to have_attributes(status: "error", chips: [ "84 ms" ])
    expect(live.counts["error"]).to be >= 1
  end

  it "never runs the live check when the host turned it off" do
    adapter = woodpecker
    allow(WarpEngine).to receive(:ci).and_return(adapter)
    allow(adapter).to receive(:ping)
    allow(WarpEngine.config).to receive(:sys_info_live_checks).and_return(false)

    live = described_class.new(live: true)

    expect(live).not_to be_live
    expect(find("ci.live", live.tree).hint).to include("sys_info_live_checks false")
    expect(adapter).not_to have_received(:ping)
  end

  it "says when the CI is off and sign-in is not configured" do
    allow(WarpEngine).to receive(:ci).and_return(WarpEngine::CI::Null.new)
    allow(WarpEngine.config).to receive(:access_token_owner_class).and_return(nil)

    expect(group("ci").rolled_status).to eq("off")
    expect(group("signin").rolled_status).to eq("off")
    expect(info).not_to be_live_available
  end

  it "reports an invalid outlet configuration instead of failing" do
    allow(WarpEngine::Outlets).to receive(:validate!).and_raise(WarpEngine::ConfigurationError, "two outlets share the key x")

    expect(find("outlets.invalid")).to have_attributes(status: "error", hint: "two outlets share the key x")
    expect(info.stats.find { |stat| stat.label == "Outlets" }.value).to eq("?")
  end

  it "shows a shelf that is not built yet as one to check" do
    container = Dir.mktmpdir
    allow(WarpEngine.config).to receive_messages(
      file_container_path: container,
      outlets: [ { key: "c64", type: "shelf", platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG" } ]
    )

    expect(find("outlets.c64.folder")).to have_attributes(status: "warn", chips: [ "not built yet" ])
    expect(find("outlets.c64.urls").status).to eq("off")
    expect(group("outlets").rolled_status).to eq("warn")
  ensure
    FileUtils.rm_rf(container)
  end

  it "counts the catalog" do
    software = create(:software, status: "released")
    create(:release, software: software, version: "1.0.0")

    labels = info.stats.to_h { |stat| [ stat.label, stat.value ] }

    expect(labels).to include("Softwares" => 1, "Releases" => 1, "Downloads" => 0)
  end

  describe "runtimes" do
    let(:container) { Dir.mktmpdir }

    before { allow(WarpEngine.config).to receive(:file_container_path).and_return(container) }

    after { FileUtils.rm_rf(container) }

    it "calls a bound runtime that is not installed an error and an uploaded one not sent yet a warning" do
      expect(find("runtimes.emulatorjs.version")).to have_attributes(status: "error", value: "4.2.3 not installed")
      expect(find("runtimes.emulatorjs.platforms").chips).to contain_exactly("c64", "plus4", "dos")
      expect(find("runtimes.tic80.version")).to have_attributes(status: "warn", value: "none uploaded")
    end

    it "lists the components the bindings need and flags a missing one" do
      version = WarpEngine::RuntimeVersion.create!(name: "emulatorjs", version: "4.2.3", source: "download",
                                                   path: "_runtimes/emulatorjs-4.2.3", files: {}, size_bytes: 1024)
      version.runtime_components.create!(kind: "core", key: "vice_x64sc")

      expect(find("runtimes.emulatorjs.version")).to have_attributes(status: "ok", value: "4.2.3")
      expect(find("runtimes.emulatorjs.components"))
        .to have_attributes(status: "error", chips: [ "core vice_x64sc", "core vice_xplus4 (missing)", "core dosbox_pure (missing)" ])
      expect(info.stats.find { |stat| stat.label == "Runtimes" }.value).to eq(1)
    end

    it "shows each platform's web bindings, the default marked" do
      expect(find("platforms.c64.web")).to have_attributes(status: "ok", chips: [ "emulatorjs default" ])
      expect(find("platforms.godot.web")).to have_attributes(status: "off", value: "no runtime")
    end
  end
end
