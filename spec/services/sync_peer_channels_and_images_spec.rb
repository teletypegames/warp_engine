require "rails_helper"
require "webmock/rspec"
require "digest"
require_relative "../support/sync_helpers"

RSpec.describe "Sync: a peer's own channels and the images" do
  include SyncHelpers
  include ActiveJob::TestHelper

  let!(:server) { sync_peer(label: "Other", host: "https://other.example/warp", secret: "other-token") }
  let(:software) { create(:software, name: "game", platform: "c64", status: "released") }

  before { sync_config(allowed_channels: WarpEngine::Channels::ALL) }

  describe "the channels of a peer" do
    it "narrows the pushes after a publish" do
      server.update!(allowed_channels: %w[stable])
      wide = sync_peer(label: "Wide", host: "https://wide.example")
      beta = create(:release, software: software, version: "1.0.0-beta.1")

      events = WarpEngine::SyncService.new.dispatch(beta)

      expect(events.map(&:sync_peer)).to eq([ wide ])
    end

    it "names the peer when it holds a release back" do
      server.update!(allowed_channels: "stable")
      beta = create(:release, software: software, version: "1.0.0-beta.1")

      expect(WarpEngine::Sync::Filter.new(WarpEngine::Sync.config.outbound).for(server).reason(beta))
        .to eq("the beta channel is not in Other's channels")
    end

    it "never widens the global list" do
      sync_config(allowed_channels: %w[stable])
      server.update!(allowed_channels: %w[stable beta])
      beta = create(:release, software: software, version: "1.0.0-beta.1")

      expect(WarpEngine::SyncService.new.dispatch(beta)).to be_empty
    end
  end

  describe "the images" do
    let(:image_dir) { Image.upload_path }

    let(:written) { [] }

    after { written.each { |path| FileUtils.rm_f(path) } }

    def gallery_image(body, default: false)
      FileUtils.mkdir_p(image_dir)
      image = create(:image, filename: "sync-#{SecureRandom.hex(6)}.png")
      File.binwrite(image.file_path, body)
      written << image.file_path
      WarpEngine::SoftwareImage.create!(software: software, image: image, is_default: default,
                                        position: software.software_images.count)
    end

    before { create(:release, software: software, version: "1.0") }

    it "queues one gallery push per peer after a change, and none for images that came by sync" do
      expect { WarpEngine::SyncService.new.dispatch_images(software) }.to have_enqueued_job(WarpEngine::SyncImagesJob).exactly(:once)
      expect { WarpEngine::SyncService.new.dispatch_images(software) }.not_to have_enqueued_job
      expect { WarpEngine::SyncService.new.dispatch_images(software, origin: "sync") }.not_to have_enqueued_job
    end

    it "publishes every change of a gallery" do
      payloads = []
      subscriber = ActiveSupport::Notifications.subscribe("warp_engine.software_images") { |*, payload| payloads << payload }
      gallery_image("one")
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(payloads).to include(software_id: software.id, origin: "local")
    end

    it "sends the manifest, uploads what the other side lacks, and sends the manifest again" do
      first = gallery_image("one", default: true)
      second = gallery_image("two")
      manifests = []
      stub_request(:post, "https://other.example/warp/build/images")
        .to_return do |request|
          manifests << JSON.parse(request.body)
          missing = manifests.size == 1 ? [ second.sha256 ] : []
          { status: 200, body: { applied: missing.empty?, missing: missing }.to_json }
        end
      upload = stub_request(:post, %r{\Ahttps://other.example/warp/build/images/upload\?})
               .with(query: hash_including("name" => "game", "sha256" => second.sha256))
               .to_return(status: 200, body: "{}")

      result = WarpEngine::SyncPushService.new.push_images(software, server)

      expect(result.status).to eq("succeeded")
      expect(upload).to have_been_requested.once
      expect(manifests.last["images"].pluck("sha256")).to eq([ first.sha256, second.sha256 ])
      expect(manifests.last["images"].first["default"]).to be(true)
      expect(WarpEngine::SyncEvent.last).to have_attributes(step: "images", status: "succeeded", files_count: 2)
    end

    it "takes a 409 as skipped" do
      gallery_image("one")
      stub_request(:post, "https://other.example/warp/build/images")
        .to_return(status: 409, body: { error: "the images of game were set here" }.to_json)

      expect(WarpEngine::SyncPushService.new.push_images(software, server).status).to eq("skipped")
    end
  end
end
