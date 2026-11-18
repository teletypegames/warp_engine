require "rails_helper"
require "webmock/rspec"
require "tmpdir"

RSpec.describe WarpEngine::Sync::Client do
  let(:client) { described_class.new(host: "https://other.example/warp/", secret: "tok3n", timeout: 5) }

  it "streams a file to /build/upload as multipart, with the token and the digest" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "game-1.0.prg")
      File.binwrite(path, "\x01\x08PRG".b)
      stub = stub_request(:post, "https://other.example/warp/build/upload?name=game&version=1.0&sha256=abc")
               .with(headers: { "X-Update-Secret" => "tok3n" }) { |request|
                 request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") &&
                   request.body.b.include?(%(filename="game-1.0.prg")) && request.body.b.include?("\x01\x08PRG".b) &&
                   request.headers["Content-Length"].to_i == request.body.bytesize
               }
               .to_return(status: 200, body: { file: "game-1.0.prg" }.to_json, headers: { "WarpEngine-Version" => "4.5.0" })

      response = client.upload(name: "game", version: "1.0", path: path, sha256: "abc")

      expect(stub).to have_been_requested
      expect(response).to be_success
      expect(response.version).to eq("4.5.0")
    end
  end

  it "publishes with the platform and the commit" do
    stub_request(:post, "https://other.example/warp/build/publish?name=game&platform=c64&version=1.0&commit=abcdef0")
      .to_return(status: 409, body: { error: "game 1.0 is older than 1.1" }.to_json)

    response = client.publish(name: "game", platform: "c64", version: "1.0", commit: "abcdef0")

    expect(response).not_to be_success
    expect(response.status).to eq(409)
    expect(response.message).to include("older")
  end

  it "asks for the builds of a software" do
    stub_request(:get, "https://other.example/warp/api/softwares/my%20game/builds")
      .to_return(status: 200, body: { releases: { "1.0" => { actual: %w[cartridge] } } }.to_json)

    expect(client.builds("my game").body.dig("releases", "1.0", "actual")).to eq(%w[cartridge])
  end

  it "checks the token with an upload without a file" do
    stub_request(:post, "https://other.example/warp/build/upload").to_return(status: 400, body: "{}")

    expect(client.check.status).to eq(400)
  end

  it "raises a ConnectionError when the host does not answer" do
    stub_request(:post, "https://other.example/warp/build/upload").to_raise(Errno::ECONNREFUSED)

    expect { client.check }.to raise_error(WarpEngine::Sync::ConnectionError, /other.example/)
  end

  it "reads its body stream in pieces" do
    stream = described_class::Multipart.new([ StringIO.new("ab"), StringIO.new("cde") ])

    expect(stream.read(4)).to eq("abcd")
    expect(stream.read(4)).to eq("e")
    expect(stream.read(4)).to be_nil
  end
end
