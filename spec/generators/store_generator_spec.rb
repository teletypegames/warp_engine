require "rails_helper"
require "generators/warp_engine/store/store_generator"

RSpec.describe WarpEngine::Generators::StoreGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def generate(*args)
    described_class.start(args, destination_root: @root, quiet: true)
    JSON.parse(File.read(File.join(@root, "public/stores/#{args.first}/config.json")))
  end

  it "names the store and brings a local logo along for Batocera" do
    logo = File.join(@root, "studio-logo.png")
    File.binwrite(logo, "png")

    config = generate("batocera", "--base-url", "http://192.168.1.20:8080", "--name", "My Studio", "--id", "mystudio",
                      "--logo", logo, "https://cdn.example/logo.svg")

    expect(config["store"]).to include("id" => "mystudio", "name" => "My Studio", "base_url" => "http://192.168.1.20:8080")
    expect(config.dig("emulationstation", "menu", "logo"))
      .to eq([ "http://192.168.1.20:8080/stores/batocera/studio-logo.png", "https://cdn.example/logo.svg" ])
    expect(File.binread(File.join(@root, "public/stores/batocera/studio-logo.png"))).to eq("png")
  end

  it "makes the PNG the RetroArch playlist icon" do
    config = generate("retroarch", "--base-url", "https://games.example", "--logo", "https://games.example/a.svg",
                      "https://games.example/b.png")

    expect(config.dig("playlist", "icon")).to eq("https://games.example/b.png")
    expect(config["paths"]).to have_key("assets_dir")
  end

  it "leaves the logo out without one" do
    expect(generate("batocera", "--base-url", "https://games.example").dig("emulationstation", "menu", "logo")).to be_nil
    expect(generate("retroarch", "--base-url", "https://games.example").dig("playlist", "icon")).to be_nil
  end

  it "refuses a logo file that is not there" do
    expect { described_class.start([ "batocera", "--base-url", "https://games.example", "--logo", "/no/such.png" ],
                                   destination_root: @root, quiet: true) }
      .to output(/no such logo file/).to_stderr
    expect(File.exist?(File.join(@root, "public/stores/batocera/config.json"))).to be(false)
  end
end
