require "rails_helper"

RSpec.describe WarpEngine::StoreClientService do
  subject(:service) { described_class.new }

  let(:tmpdir) { Dir.mktmpdir }
  let(:engine) { create(:software, name: "we-batocera", platform: "batocera") }

  before { allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  def release(version, created_at: Time.current, archive: true)
    create(:release, software: engine, version: version, created_at: created_at).tap do |release|
      next unless archive

      path = File.join(tmpdir, "softwares/we-batocera/#{version}/we-batocera-#{version}.tar.gz")
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "x" * 7)
      release.release_assets.create!(kind: "cartridge", path: path)
    end
  end

  describe "#release" do
    it "runs the newest stable release that has its archive" do
      release("4.3.0", created_at: 2.days.ago)
      release("4.4.0", created_at: 1.day.ago)
      release("4.5.0-dev.3")
      release("4.6.0", archive: false)

      expect(service.release(client: "batocera"))
        .to eq(described_class::Target.new(software: "we-batocera", version: "4.4.0",
                                           path: "softwares/we-batocera/4.4.0/we-batocera-4.4.0.tar.gz", size: 7))
    end

    it "runs the pinned version instead" do
      release("4.3.0", created_at: 2.days.ago)
      release("4.4.0", created_at: 1.day.ago)
      WarpEngine::StoreClient.create!(client: "batocera", pinned_version: "4.3.0")

      expect(service.release(client: "batocera").version).to eq("4.3.0")
    end

    it "reads the software the host names" do
      other = create(:software, name: "my-batocera", platform: "batocera")
      create(:release, software: other, version: "1.0.0").release_assets.create!(kind: "cartridge", path: "/x/a.tar.gz")
      WarpEngine::StoreClient.create!(client: "batocera", software_name: "my-batocera")

      expect(service.release(client: "batocera")).to have_attributes(software: "my-batocera", version: "1.0.0", size: nil)
    end

    it "says there is nothing to run" do
      expect { service.release(client: "batocera") }.to raise_error(ActiveRecord::RecordNotFound)
      engine
      expect { service.release(client: "batocera") }.to raise_error(ActiveRecord::RecordNotFound, /no release/)
      expect { service.release(client: "pegasus") }.to raise_error(ActiveRecord::RecordNotFound, /not a store engine/)
    end
  end

  describe "#config" do
    it "fills the template from the catalog when the host set nothing" do
      config = service.config(client: "batocera", base_url: "https://www.games.example/", release_path: "/api/stores/batocera/release")

      expect(config["store"]).to include("id" => "games", "name" => "www.games.example", "base_url" => "https://www.games.example")
      expect(config.dig("store", "api", "release")).to eq("/api/stores/batocera/release")
      expect(config.dig("paths", "subfolder")).to eq("games")
      expect(config.dig("emulationstation", "folder_name")).to eq("www.games.example")
      expect(config.dig("catalog", "statuses")).to eq(WarpEngine::SoftwareStatus.default_visible_keys)
      expect(config.dig("emulationstation", "menu", "logo")).to be_nil
      expect(config["platforms"].keys).to all(satisfy { |name| WarpEngine::Platform.exists?(name) })
    end

    it "takes what the host set" do
      WarpEngine::StoreClient.create!(client: "retroarch", name: "Teletype Games", store_key: "ttg", subfolder: "teletypegames",
                                      statuses: %w[released], logo_urls: %w[https://x.example/l.svg https://x.example/l.png])

      config = service.config(client: "retroarch", base_url: "https://teletypegames.org", release_path: "/r")

      expect(config["store"]).to include("id" => "ttg", "name" => "Teletype Games")
      expect(config.dig("paths", "subfolder")).to eq("teletypegames")
      expect(config.dig("catalog", "statuses")).to eq(%w[released])
      expect(config.dig("playlist", "icon")).to eq("https://x.example/l.png")
    end
  end

  describe "#installer" do
    it "downloads the release and runs its installer with the store config" do
      release("4.4.0")

      script = service.installer(client: "batocera", base_url: "https://games.example",
                                 install_url: "https://games.example/api/stores/batocera/install.sh",
                                 config_url: "https://games.example/api/stores/batocera/config.json",
                                 archive_url: "https://games.example/api/download?path=x")

      expect(script).to start_with("#!/bin/sh\n# games.example on Batocera: we-batocera 4.4.0\n")
      expect(script).to include('STORE_CONFIG="${STORE_CONFIG:-https://games.example/api/stores/batocera/config.json}"',
                                'ENGINE_ARCHIVE="${ENGINE_ARCHIVE:-https://games.example/api/download?path=x}"',
                                'sh "$INSTALLER"')
    end
  end
end
