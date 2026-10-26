require "rails_helper"

module RegistrySpec
  class AmigaService
    include WarpEngine::Platforms::Updatable
    include WarpEngine::Platforms::Builds::BuildCartridge

    platform "amiga"
    label "Amiga"
    required_kinds "cartridge"

    def cartridge_ext = ".adf"
  end
end

RSpec.describe "Platforms a host registers" do
  let(:config) { WarpEngine::Configuration.new }
  let(:templates) { Dir.mktmpdir }

  before do
    File.write(File.join(templates, "amiga.yaml.erb"), "steps:\n  - name: build\n    image: <%= builder %>\n    commands: [ \"echo <%= name %>\" ]\n")
    config.register_platform "amiga", service: "RegistrySpec::AmigaService", built_kinds: %w[cartridge],
                                      templates: { woodpecker: File.join(templates, "amiga.yaml.erb") }
    allow(WarpEngine).to receive(:config).and_return(config)
  end

  after { FileUtils.remove_entry(templates) }

  it "joins the built-in platforms, with its own service, label and kinds" do
    platform = WarpEngine::Platform.find!("amiga")

    expect(WarpEngine::Platform.names).to include("amiga", "c64", "dos")
    expect(platform.label).to eq("Amiga")
    expect(platform.expected_kinds).to eq([ "cartridge" ])
    expect(platform.required_kinds).to eq([ "cartridge" ])
  end

  it "is a platform a software may be on" do
    expect(build(:software, platform: "amiga")).to be_valid
    expect(build(:software, platform: "atari")).not_to be_valid
  end

  it "brings its own pipeline template and built kinds" do
    ci = WarpEngine::CI::Woodpecker::PipelineConfig.new(platforms: { "amiga" => { builder: "registry.example/vbcc:1" } })

    expect(ci.render(platform: "amiga", name: "lemmings", update_server: "u")).to include("registry.example/vbcc:1", "echo lemmings")
    expect(ci.built_kinds("amiga")).to eq([ "cartridge" ])
    expect(WarpEngine::CI::Gitlab::PipelineConfig.new(platforms: { "amiga" => { builder: "b" } })
             .render(platform: "amiga", name: "lemmings", update_server: "u")).to be_nil
  end

  it "refuses a name that is not a slug" do
    expect { config.register_platform "Amiga 500", service: "X" }.to raise_error(ArgumentError)
  end
end
