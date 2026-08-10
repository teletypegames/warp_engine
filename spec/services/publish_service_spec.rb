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
    describe "instrumentation" do
      let(:input) { WarpEngine::PublishInputDto.new(platform: "tic80", name: "game", version: "1.0") }
      let(:release) { WarpEngine::Release.new(version: "1.0") }

      before do
        mock_service = instance_double(WarpEngine::Platforms::Tic80::Service, update: release)
        allow(WarpEngine::Platforms::Tic80::Service).to receive(:new).and_return(mock_service)
      end

      # The host reacts to a new build through this event instead of hanging a
      # callback on the Release model.
      it "emits warp_engine.publish with the release in the payload" do
        payloads = []
        ActiveSupport::Notifications.subscribe(described_class::NOTIFICATION) do |*, payload|
          payloads << payload
        end

        described_class.new.publish(input)

        expect(payloads.size).to eq(1)
        expect(payloads.first).to include(platform: "tic80", name: "game", version: "1.0", release: release)
      ensure
        ActiveSupport::Notifications.unsubscribe(described_class::NOTIFICATION)
      end

      it "returns the release" do
        expect(described_class.new.publish(input)).to eq(release)
      end

      it "advertises the feature so older hosts can feature-detect" do
        expect(WarpEngine.instruments_publish?).to be(true)
      end
    end
  end
end
