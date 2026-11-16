require "rails_helper"

RSpec.describe WarpEngine::Runtime do
  describe "the builtin runtimes" do
    it "ships EmulatorJS, downloaded with a checksum per file, and TIC-80, uploaded by a build" do
      expect(described_class.names).to include("emulatorjs", "tic80")
      expect(described_class.find!("emulatorjs")).to be_download
      expect(described_class.find!("tic80")).to be_upload
    end

    it "takes the EmulatorJS files from its checksum list and splits them into base files and cores" do
      definition = described_class.find!("emulatorjs").definition
      checksums = definition.versions.fetch("4.2.3").checksums

      expect(definition.base_files("4.2.3")).to contain_exactly("loader.js", "emulator.min.js", "emulator.min.css",
                                                                 "version.json", "compression/extract7z.js")
      expect(definition.components.fetch("core").files("vice_x64sc", checksums))
        .to contain_exactly("cores/vice_x64sc-wasm.data", "cores/vice_x64sc-legacy-wasm.data", "cores/reports/vice_x64sc.json")
      expect(definition.components.fetch("core").files("dosbox_pure", checksums))
        .to include("cores/dosbox_pure-thread-wasm.data")
      expect(checksums.values).to all(match(/\A\h{64}\z/))
    end

    it "knows no platform; the platforms bound to it are read from their bindings" do
      runtime = described_class.find!("emulatorjs")

      expect(runtime.platforms).to contain_exactly("c64", "plus4")
      expect(runtime.required_components).to eq("core" => %w[vice_x64sc vice_xplus4])
    end
  end

  describe "parameters" do
    let(:definition) { described_class.find!("emulatorjs").definition }

    it "starts from the defaults and lets later layers win, merging a Hash one level deep" do
      params = definition.resolve_params({ core: "vice_x64sc", options: { "a" => 1 } }, { "options" => { "b" => 2 } })

      expect(params).to include("core" => "vice_x64sc", "options" => { "a" => 1, "b" => 2 })
      expect(params["controls"]).to eq(described_class::KEYBOARD_TO_MACHINE)
    end

    it "names an unknown parameter, a missing required one and a wrong type" do
      expect(definition.param_errors({ core: "x" })).to be_empty
      expect(definition.param_errors({ colour: "red", options: "x" }))
        .to contain_exactly("unknown parameter colour", "core is required", "options must be a hash")
    end
  end

  describe "the version" do
    it "is the newest declared one unless the host chose another" do
      runtime = described_class.find!("emulatorjs")
      expect(runtime.chosen_version).to eq("4.2.3")

      allow(WarpEngine.config).to receive(:runtime_versions).and_return("emulatorjs" => "4.1.0")
      expect(runtime.chosen_version).to eq("4.1.0")
    end

    it "is, for an uploaded runtime without a choice, the newest installed one" do
      allow(WarpEngine.config).to receive(:file_container_path).and_return(Dir.mktmpdir)
      install_runtime_version(name: "tic80", version: "1.0", files: { "tic80.js" => "a" }, source: "upload")
      newer = install_runtime_version(name: "tic80", version: "1.1", files: { "tic80.js" => "b" }, source: "upload")

      expect(described_class.find!("tic80").current_version).to eq(newer)
    end
  end

  describe "a host's runtime" do
    it "is registered with the same DSL and listed after the builtin ones" do
      config = WarpEngine::Configuration.new
      config.register_runtime("ruffle") do
        label "Ruffle"
        source :upload
        files "ruffle.js", "*.wasm"
        template "tic80.html"
      end

      allow(WarpEngine).to receive(:config).and_return(config)
      expect(described_class.names.last).to eq("ruffle")
      expect(described_class.find!("ruffle").label).to eq("Ruffle")
    end

    it "refuses a malformed name, a missing template and a downloaded runtime without a version" do
      config = WarpEngine::Configuration.new

      expect { config.register_runtime("Bad Name") }.to raise_error(ArgumentError, /must match/)
      expect { config.register_runtime("nothing") { source :upload; template "/nope.html" } }.to raise_error(ArgumentError, /no template/)
      expect { config.register_runtime("bare") { template "tic80.html" } }.to raise_error(ArgumentError, /needs a version/)
    end
  end

  describe WarpEngine::Runtime::Template do
    it "escapes a value for HTML and writes JSON that cannot close a script" do
      html = described_class.render("<h1>{{ title }}</h1><script>x = {{ json params.name }}; y = {{ json missing }}</script>",
                                    "title" => "A & <B>", "params" => { "name" => "</script>" })

      expect(html).to eq('<h1>A &amp; &lt;B&gt;</h1><script>x = "\\u003c/script\\u003e"; y = null</script>')
    end
  end
end
