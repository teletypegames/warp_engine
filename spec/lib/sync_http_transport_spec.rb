require "rails_helper"
require "webmock/rspec"
require "tmpdir"
require_relative "../support/sync_helpers"

RSpec.describe WarpEngine::Sync::Transports::Http do
  include SyncHelpers

  let(:peer) { sync_peer(host: "https://other.example/warp/", secret: "tok3n") }
  let(:transport) { described_class.new(peer) }
  let(:software) { build(:software, name: "game", platform: "c64") }
  let(:release) { build(:release, software: software, version: "1.0") }

  def package(files)
    WarpEngine::Sync::Package.new(release: release, software: software, platform: WarpEngine::Platform.find!("c64"),
                                  files: files, commit: "abcdef0")
  end

  it "is the builtin http transport with a host and a secret token" do
    expect(WarpEngine::Sync::Transports.find("http")).to eq(described_class)
    expect(described_class.options.map(&:name)).to eq(%w[host token])
    expect(described_class.options.find(&:secret).name).to eq("token")
    expect(described_class).to be_publishes
  end

  it "streams every file as multipart under its name, then publishes" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "old-1.0.prg")
      File.binwrite(path, "\x01\x08PRG".b)
      upload = stub_request(:post, "https://other.example/warp/build/upload")
                 .with(query: hash_including("name" => "game", "version" => "1.0"), headers: { "X-Update-Secret" => "tok3n" }) { |request|
                   request.body.b.include?(%(filename="game-1.0.prg")) && request.body.b.include?("\x01\x08PRG".b) &&
                     request.headers["Content-Length"].to_i == request.body.bytesize
                 }.to_return(status: 200, body: "{}")
      publish = stub_request(:post, "https://other.example/warp/build/publish?name=game&platform=c64&version=1.0&commit=abcdef0")
                  .to_return(status: 200, body: "{}")
      steps = []

      delivery = transport.deliver(package([ WarpEngine::Sync::PackageFile.new(path: path, name: "game-1.0.prg", kind: "cartridge") ])) { |step| steps << step }

      expect(delivery.status).to eq("succeeded")
      expect(steps).to eq([ "upload:game-1.0.prg", "publish" ])
      expect(upload).to have_been_requested
      expect(publish).to have_been_requested
    end
  end

  it "takes a 403 or 409 as skipped and another refusal as failed" do
    stub_request(:post, %r{/build/publish}).to_return(status: 403, body: { error: "sync inbound: c64 only" }.to_json)
    expect(transport.deliver(package([]))).to have_attributes(status: "skipped", code: 403, message: "sync inbound: c64 only")

    stub_request(:post, %r{/build/publish}).to_return(status: 500, body: "")
    expect(transport.deliver(package([]))).to have_attributes(status: "failed", code: 500)
  end

  it "reads what the other engine has, without the token" do
    stub = stub_request(:get, "https://other.example/warp/api/softwares/game/builds")
             .with { |request| request.headers["X-Update-Secret"].nil? }
             .to_return(status: 200, body: { releases: { "1.0" => { actual: %w[cartridge] } } }.to_json)

    expect(transport.existing(package([]))).to eq(%w[cartridge])
    expect(stub).to have_been_requested

    stub_request(:get, %r{/builds}).to_return(status: 404)
    expect(transport.existing(package([]))).to eq([])

    stub_request(:get, %r{/builds}).to_raise(Errno::ECONNREFUSED)
    expect(transport.existing(package([]))).to be_nil
  end

  it "checks the token with an upload without a file" do
    stub_request(:post, "https://other.example/warp/build/upload").to_return(status: 400, headers: { "WarpEngine-Version" => "5.0.0" })
    expect(transport.check).to have_attributes(ok: true, version: "5.0.0")

    stub_request(:post, "https://other.example/warp/build/upload").to_return(status: 401)
    expect(transport.check).to have_attributes(ok: false, message: a_string_including("sync scope"))
  end

  it "raises Unreachable when the host does not answer" do
    stub_request(:post, %r{/build/publish}).to_raise(Errno::ECONNREFUSED)

    expect { transport.deliver(package([])) }.to raise_error(WarpEngine::Sync::Transport::Unreachable, /other.example/)
  end

  it "reads its body stream in pieces" do
    stream = described_class::Multipart.new([ StringIO.new("ab"), StringIO.new("cde") ])

    expect(stream.read(4)).to eq("abcd")
    expect(stream.read(4)).to eq("e")
    expect(stream.read(4)).to be_nil
  end

  it "wants an https host outside development and test, and a token on an outbound peer" do
    expect(described_class.errors_for(WarpEngine::SyncPeer.new(label: "x", outbound_enabled: true, transport_options: { "host" => "nope" })))
      .to include("Host must be an http(s) URL", "Token is required")
  end

  it "takes plain http outside development and test only to this machine or a private network" do
    allow(Rails.env).to receive(:local?).and_return(false)
    errors = ->(host) { described_class.errors_for(WarpEngine::SyncPeer.new(label: "x", outbound_enabled: false, transport_options: { "host" => host })) }

    expect(errors.call("http://games.example.org")).to eq([ "Host must use https" ])
    %w[http://localhost:8081 http://host.docker.internal:8081 http://10.0.0.5 http://192.168.1.2 http://[::1]:3000].each do |host|
      expect(errors.call(host)).to be_empty, host
    end
  end
end
