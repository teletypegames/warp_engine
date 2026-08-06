require "rails_helper"

RSpec.describe WarpEngine::PublishService do
  describe "#publish" do
    it "raises ArgumentError for unsupported platform" do
      input = WarpEngine::PublishInputDto.new(platform: "unknown", name: "game", version: "1.0")

      expect { described_class.new.publish(input) }.to raise_error(ArgumentError, /Unsupported platform/)
    end

    it "routes to correct platform service" do
      input = WarpEngine::PublishInputDto.new(platform: "tic80", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::Platforms::Tic80::Service)

      allow(WarpEngine::Platforms::Tic80::Service).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.publish(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes godot platform to Godot::Service" do
      input = WarpEngine::PublishInputDto.new(platform: "godot", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::Platforms::Godot::Service)

      allow(WarpEngine::Platforms::Godot::Service).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.publish(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes bevy platform to Bevy::Service" do
      input = WarpEngine::PublishInputDto.new(platform: "bevy", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::Platforms::Bevy::Service)

      allow(WarpEngine::Platforms::Bevy::Service).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.publish(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end

    it "routes phaser platform to Phaser::Service" do
      input = WarpEngine::PublishInputDto.new(platform: "phaser", name: "game", version: "1.0")
      mock_service = instance_double(WarpEngine::Platforms::Phaser::Service)

      allow(WarpEngine::Platforms::Phaser::Service).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:update)

      described_class.new.publish(input)

      expect(mock_service).to have_received(:update).with("game", "1.0")
    end
  end
end
