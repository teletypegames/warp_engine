require "rails_helper"
require_relative "../support/forks_helpers"

RSpec.describe WarpEngine::ForkService do
  include ForksHelpers
  include ActiveJob::TestHelper

  let(:parent) { create(:software, name: "parent", title: "Parent") }
  let(:engine_url) { "https://other.example" }
  let(:catalog) { { "softwares" => [ { "software" => { "name" => "mine", "title" => "Mine", "forkOf" => { "engine" => "https://games.example", "name" => "parent" } } } ] } }
  let(:fetched) { [] }
  let(:service) do
    described_class.new(fetcher: lambda { |url|
      fetched << url
      catalog
    }, cache: ActiveSupport::Cache::MemoryStore.new)
  end

  before { configure_forks(engine_url: "https://games.example", accept_announcements: true, announce: true) }

  describe "#receive" do
    it "queues a verification of a well-formed announcement" do
      expect { service.receive(engine: "#{engine_url}/", name: "mine", remote_ip: "1.2.3.4") }
        .to have_enqueued_job(WarpEngine::ForkVerifyJob).with(engine_url, "mine")
    end

    it "refuses a malformed engine or name" do
      expect { service.receive(engine: "ftp://x", name: "mine") }.to raise_error(described_class::InvalidAnnouncement)
      expect { service.receive(engine: engine_url, name: "../etc") }.to raise_error(described_class::InvalidAnnouncement)
    end

    it "drops a denied engine quietly" do
      configure_forks(engine_url: "https://games.example", accept_announcements: true, denied_engines: %w[other.example])

      expect(service.receive(engine: engine_url, name: "mine")).to be(false)
    end

    it "limits the announcements of one address" do
      configure_forks(engine_url: "https://games.example", accept_announcements: true, announcements_per_hour: 2)
      2.times { service.receive(engine: engine_url, name: "mine", remote_ip: "1.2.3.4") }

      expect { service.receive(engine: engine_url, name: "mine", remote_ip: "1.2.3.4") }.to raise_error(described_class::RateLimited)
    end
  end

  describe "#verify" do
    it "records a fork that names our software as pending and announces it" do
      parent
      events = []
      callback = ->(*, payload) { events << payload }

      link = ActiveSupport::Notifications.subscribed(callback, described_class::NOTIFICATION) do
        service.verify(engine: engine_url, name: "mine")
      end

      expect(link).to have_attributes(software: parent, title: "Mine", status: "pending")
      expect(events.size).to eq(1)
      expect(fetched).to eq([ "#{engine_url}/api/software?q=mine" ])
    end

    it "lists it at once under auto moderation" do
      parent
      configure_forks(engine_url: "https://games.example", moderation: :auto)

      expect(service.verify(engine: engine_url, name: "mine").status).to eq("visible")
    end

    it "keeps the administrator's decision on a second announcement" do
      parent
      service.verify(engine: engine_url, name: "mine").update!(status: "hidden")

      expect(service.verify(engine: engine_url, name: "mine").status).to eq("hidden")
    end

    it "does not record a fork that names someone else" do
      parent
      catalog["softwares"][0]["software"]["forkOf"]["engine"] = "https://elsewhere.example"

      expect(service.verify(engine: engine_url, name: "mine")).to be_nil
      expect(WarpEngine::SoftwareFork.count).to eq(0)
    end

    it "does not record a fork the child engine does not list" do
      parent
      catalog["softwares"] = []

      expect(service.verify(engine: engine_url, name: "mine")).to be_nil
    end

    it "does not fetch from a private address" do
      configure_forks(engine_url: "https://games.example", allow_private_engines: false)

      expect(service.verify(engine: "http://127.0.0.1:3000", name: "mine")).to be_nil
      expect(fetched).to be_empty
    end
  end

  describe "#recheck" do
    it "marks a fork that is gone, and brings it back to moderation when it returns" do
      parent
      link = service.verify(engine: engine_url, name: "mine")
      link.update!(status: "visible")
      catalog["softwares"] = []

      expect(service.recheck(link).status).to eq("gone")
      expect(link.last_error).to include("not in the catalog")

      catalog["softwares"] = [ { "software" => { "name" => "mine", "title" => "Mine 2", "forkOf" => { "engine" => "https://games.example", "name" => "parent" } } } ]
      expect(service.recheck(link)).to have_attributes(status: "pending", title: "Mine 2")
    end
  end

  describe "#forks" do
    it "lists the local children and the visible announced forks" do
      create(:software, name: "local-child", title: "Local Child", fork_of_engine: "https://games.example", fork_of_name: "parent")
      WarpEngine::SoftwareFork.create!(software: parent, engine_url: engine_url, name: "mine", title: "Mine", status: "visible")
      WarpEngine::SoftwareFork.create!(software: parent, engine_url: engine_url, name: "waiting", status: "pending")

      expect(service.forks(parent)).to eq([
        { engine: "https://games.example", name: "local-child", title: "Local Child", local: true },
        { engine: engine_url, name: "mine", title: "Mine", local: false }
      ])
    end
  end

  describe "announcing" do
    let(:fork) { create(:software, name: "mine", fork_of_engine: "https://parent.example", fork_of_name: "parent") }

    it "queues an announcement for a fork of a software on another engine" do
      expect { service.announce_later(fork) }.to have_enqueued_job(WarpEngine::ForkAnnounceJob).with(fork.id)
    end

    it "posts this engine's URL and the fork's name to the parent" do
      posted = []
      poster = lambda { |url, body|
        posted << [ url, body ]
        202
      }

      expect(described_class.new(poster: poster).announce(fork)).to eq(202)
      expect(posted).to eq([ [ "https://parent.example/api/forks", { engine: "https://games.example", name: "mine" } ] ])
    end

    it "announces nothing from a local engine, nor for a fork of our own software" do
      allow(WarpEngine.config).to receive(:local?).and_return(true)
      expect(service.announce_later(fork)).to be(false)

      allow(WarpEngine.config).to receive(:local?).and_return(false)
      own = create(:software, fork_of_engine: "https://games.example", fork_of_name: "parent")
      expect(service.announce_later(own)).to be(false)
    end
  end
end
