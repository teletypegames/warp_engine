require "rails_helper"

RSpec.describe WarpEngine::UpdateService do
  describe "#update" do
    it "raises ArgumentError for unsupported platform" do
      input = WarpEngine::UpdateInputDto.new(platform: "unknown", name: "game", version: "1.0")

      expect { described_class.new.update(input) }.to raise_error(ArgumentError, /Unsupported platform/)
    end

    it "routes to correct platform service" do
      input = WarpEngine::UpdateInputDto.new(platform: "tic80", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::SoftwareUpdater::Tic80Service)

      allow(WarpEngine::SoftwareUpdater::Tic80Service).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.update(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes godot platform to GodotService" do
      input = WarpEngine::UpdateInputDto.new(platform: "godot", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::SoftwareUpdater::GodotService)

      allow(WarpEngine::SoftwareUpdater::GodotService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.update(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes bevy platform to BevyService" do
      input = WarpEngine::UpdateInputDto.new(platform: "bevy", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::SoftwareUpdater::BevyService)

      allow(WarpEngine::SoftwareUpdater::BevyService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.update(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes phaser platform to PhaserService" do
      input = WarpEngine::UpdateInputDto.new(platform: "phaser", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::SoftwareUpdater::PhaserService)

      allow(WarpEngine::SoftwareUpdater::PhaserService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.update(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end
  end
end
