require "rails_helper"

RSpec.describe WarpEngine::PublishService do
  describe "#publish" do
    it "raises ArgumentError for unsupported platform" do
      input = WarpEngine::PublishInputDto.new(platform: "unknown", name: "game", version: "1.0")

      expect { described_class.new.publish(input) }.to raise_error(ArgumentError, /Unsupported platform/)
    end

    %w[tic80 godot bevy phaser].each do |name|
      it "publishes #{name} through its platform" do
        input = WarpEngine::PublishInputDto.new(platform: name, name: "game", version: "1.0")
        allow(WarpEngine::Publish::Publisher).to receive(:new).and_call_original
        allow_any_instance_of(WarpEngine::Publish::Publisher).to receive(:publish).and_return(WarpEngine::Release.new)

        described_class.new.publish(input)

        expect(WarpEngine::Publish::Publisher).to have_received(:new).with(WarpEngine::Platform.find!(name).definition)
      end
    end

    describe "instrumentation" do
      let(:input) { WarpEngine::PublishInputDto.new(platform: "tic80", name: "game", version: "1.0") }
      let(:release) { WarpEngine::Release.new(version: "1.0") }

      before do
        allow(WarpEngine::Platform).to receive(:find!).and_call_original
        allow(WarpEngine::Platform).to receive(:find!).with("tic80")
                                                       .and_return(instance_double(WarpEngine::Platform, publish: release))
      end

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
