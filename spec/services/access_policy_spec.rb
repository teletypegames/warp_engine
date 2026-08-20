require "rails_helper"
require "tmpdir"

RSpec.describe "The access policy" do
  let(:tmpdir) { Dir.mktmpdir }

  let(:gating_policy) do
    Class.new do
      def initialize(open_name) = @open_name = open_name

      def visible_software_scope(subject: nil)
        WarpEngine::Software.where.not(status: "development")
      end

      def access_for(software:, subject: nil)
        return WarpEngine::Access.new if software.name == @open_name

        WarpEngine::Access.new(
          gated: true, entitled: subject.present?, price_cents: 1490, currency: "EUR",
          purchase_url: "https://shop.example/#{software.name}",
          web_url: "https://shop.example/play/#{software.name}"
        )
      end

      def authorize_download(asset: nil, subject: nil, request: nil)
        return WarpEngine::Access::Grant.new if asset&.release&.software&.name == @open_name

        subject.nil? ? nil : WarpEngine::Access::Grant.new
      end
    end
  end

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    WarpEngine::Storage.reset!
    WarpEngine::AccessPolicy.reset!
  end

  after do
    FileUtils.rm_rf(tmpdir)
    WarpEngine::AccessPolicy.reset!
  end

  describe "the default (:open) policy" do
    it "lists every software, whatever its status" do
      create(:software, status: "development")
      create(:software, status: "released")

      result = WarpEngine::SoftwareService.new.index

      expect(result[:softwares].size).to eq(2)
    end

    it "reports every title as open, so a client never has to guess" do
      create(:software)

      entry = WarpEngine::SoftwareService.new.index[:softwares].first

      expect(entry[:access]).to eq(
        gated: false, entitled: true, price: nil, purchaseUrl: nil, webUrl: nil
      )
    end

    it "hands over an artifact with no subject at all" do
      File.write(File.join(tmpdir, "game-1.0.zip"), "zip")

      path = WarpEngine::DownloadService.new.create(
        path: "game-1.0.zip", ip: "127.0.0.1", user_agent: "rspec", referer: nil
      )

      expect(path).to eq(File.join(tmpdir, "game-1.0.zip"))
    end
  end

  describe "a configured policy" do
    let(:open_software)   { create(:software, name: "free-game", status: "released") }
    let(:gated_software)  { create(:software, name: "paid-game", status: "released") }
    let(:subject_record)  { create(:test_owner) }

    before do
      open_software
      gated_software
      create(:software, name: "draft-game", status: "development")
      allow(WarpEngine.config).to receive(:access_policy).and_return(gating_policy.new("free-game"))
    end

    it "narrows the catalog to what the policy scope allows" do
      names = WarpEngine::SoftwareService.new.index[:softwares].map { |e| e[:software][:name] }

      expect(names).to contain_exactly("free-game", "paid-game")
    end

    it "describes a gated title with its price and where to buy it" do
      entry = WarpEngine::SoftwareService.new.index[:softwares]
                                         .find { |e| e[:software][:name] == "paid-game" }

      expect(entry[:access]).to eq(
        gated: true, entitled: false,
        price: { amountCents: 1490, currency: "EUR" },
        purchaseUrl: "https://shop.example/paid-game",
        webUrl: "https://shop.example/play/paid-game"
      )
    end

    it "reports entitlement against the authenticated subject" do
      entry = WarpEngine::SoftwareService.new.index(subject: subject_record)[:softwares]
                                         .find { |e| e[:software][:name] == "paid-game" }

      expect(entry[:access][:entitled]).to be(true)
    end

    it "refuses an artifact the policy will not authorise" do
      File.write(File.join(tmpdir, "paid-game-1.0.zip"), "zip")
      release = create(:release, software: gated_software)
      WarpEngine::ReleaseAsset.create!(release: release, kind: "win_x64",
                                       path: File.join(tmpdir, "paid-game-1.0.zip"))

      expect {
        WarpEngine::DownloadService.new.create(
          path: "paid-game-1.0.zip", ip: "127.0.0.1", user_agent: "rspec", referer: nil
        )
      }.to raise_error(WarpEngine::DownloadService::Denied)
    end

    it "hands the same artifact over to a subject the policy accepts" do
      File.write(File.join(tmpdir, "paid-game-1.0.zip"), "zip")
      release = create(:release, software: gated_software)
      WarpEngine::ReleaseAsset.create!(release: release, kind: "win_x64",
                                       path: File.join(tmpdir, "paid-game-1.0.zip"))

      path = WarpEngine::DownloadService.new.create(
        path: "paid-game-1.0.zip", ip: "127.0.0.1", user_agent: "rspec", referer: nil,
        subject: subject_record
      )

      expect(path).to eq(File.join(tmpdir, "paid-game-1.0.zip"))
    end
  end

  describe "a policy that raises" do
    let(:broken_policy) do
      Class.new do
        def visible_software_scope(subject: nil) = raise("boom")
        def access_for(software:, subject: nil) = raise("boom")
        def authorize_download(asset: nil, subject: nil, request: nil) = raise("boom")
      end.new
    end

    before { allow(WarpEngine.config).to receive(:access_policy).and_return(broken_policy) }

    it "empties the catalog rather than leaking it" do
      create(:software, status: "released")

      expect(WarpEngine::SoftwareService.new.index[:softwares]).to be_empty
    end

    it "refuses the download rather than serving it" do
      File.write(File.join(tmpdir, "game-1.0.zip"), "zip")

      expect {
        WarpEngine::DownloadService.new.create(
          path: "game-1.0.zip", ip: "127.0.0.1", user_agent: "rspec", referer: nil
        )
      }.to raise_error(WarpEngine::DownloadService::Denied)
    end
  end
end
