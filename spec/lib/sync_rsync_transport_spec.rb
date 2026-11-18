require "rails_helper"
require "tmpdir"
require_relative "../support/sync_helpers"
require "shellwords"

RSpec.describe WarpEngine::Sync::Transports::Rsync do
  include SyncHelpers

  let(:peer) do
    WarpEngine::SyncPeer.create!(label: "Mirror", transport: "rsync", outbound_enabled: true, secret: "-----BEGIN KEY-----\nabc\n-----END KEY-----",
                                 transport_options: { "host" => "mirror.example", "user" => "warp", "path" => "/srv/mirror/", "port" => "2222" })
  end
  let(:transport) { described_class.new(peer) }
  let(:software) { build(:software, name: "game", platform: "c64") }
  let(:release) { build(:release, software: software, version: "1.0") }
  let(:calls) { [] }

  def status(code) = instance_double(Process::Status, exitstatus: code)

  def stub_rsync(code: 0, out: "", err: "")
    allow(Open3).to receive(:capture3) do |*command|
      ssh = command[command.index("-e") + 1]
      key = Shellwords.split(ssh)[Shellwords.split(ssh).index("-i") + 1]
      calls << { command: command, ssh: ssh, key: File.read(key), staged: Dir.glob("#{command[-2]}**/*").map { |path| path.delete_prefix(command[-2]) } }
      [ out, err, status(code) ]
    end
  end

  def package(files)
    WarpEngine::Sync::Package.new(release: release, software: software, platform: WarpEngine::Platform.find!("c64"),
                                  files: files, commit: nil)
  end

  it "is a builtin file-mirror transport with a private key as its secret" do
    expect(WarpEngine::Sync::Transports.find("rsync")).to eq(described_class)
    expect(described_class).not_to be_publishes
    expect(described_class.options.find(&:secret)).to have_attributes(name: "ssh_key", type: :text)
  end

  it "wants host, user, path and key on an outbound peer, and a numeric port" do
    peer = WarpEngine::SyncPeer.new(label: "x", transport: "rsync", outbound_enabled: true, transport_options: { "port" => "ssh" })

    expect(peer).not_to be_valid
    expect(peer.errors.full_messages).to include("Host is required", "User is required", "Path is required",
                                                 "Private key is required", "Port must be a number")
  end

  it "mirrors the files under <path>/<name>/<version>/ with the key and port, over ssh" do
    stub_rsync
    Dir.mktmpdir do |dir|
      prg = File.join(dir, "old-1.0.prg").tap { |path| File.write(path, "prg") }
      meta = File.join(dir, "game-1.0.metadata.json").tap { |path| File.write(path, "{}") }
      steps = []

      delivery = transport.deliver(package([ WarpEngine::Sync::PackageFile.new(path: prg, name: "game-1.0.prg", kind: "cartridge"),
                                             WarpEngine::Sync::PackageFile.new(path: meta, name: "game-1.0.metadata.json", kind: nil) ])) { |step| steps << step }

      expect(delivery.status).to eq("succeeded")
      expect(steps).to eq([ "upload:game/1.0" ])
      call = calls.last
      expect(call[:command].first(2)).to eq(%w[rsync --protect-args])
      expect(call[:command].last).to eq("warp@mirror.example:/srv/mirror/")
      expect(call[:staged]).to include("game/1.0/game-1.0.prg", "game/1.0/game-1.0.metadata.json")
      expect(call[:ssh]).to include("-p 2222", "BatchMode=yes", "StrictHostKeyChecking=accept-new")
      expect(call[:key]).to eq("-----BEGIN KEY-----\nabc\n-----END KEY-----\n")
    end
  end

  it "trusts only the given host key" do
    peer.update!(transport_options: peer.transport_options.merge("host_key" => "mirror.example ssh-ed25519 AAAA"))
    stub_rsync

    transport.check

    expect(calls.last[:ssh]).to include("StrictHostKeyChecking=yes")
  end

  it "reads which kinds are there from a listing" do
    listing = <<~OUT
      drwxr-xr-x          4,096 2026/11/18 21:11:00 .
      -rw-r--r--          8,072 2026/11/18 21:11:00 game-1.0.prg
      -rw-r--r--            120 2026/11/18 21:11:00 game-1.0.metadata.json
    OUT
    stub_rsync(out: listing)
    files = [ WarpEngine::Sync::PackageFile.new(path: "/x", name: "game-1.0.prg", kind: "cartridge"),
              WarpEngine::Sync::PackageFile.new(path: "/y", name: "game-1.0-win-x64.zip", kind: "win_x64") ]

    expect(transport.existing(package(files))).to eq(%w[cartridge])
    expect(calls.last[:command].last).to eq("warp@mirror.example:/srv/mirror/game/1.0/")
  end

  it "takes a missing folder as nothing there" do
    stub_rsync(code: 23, err: "change_dir failed: No such file or directory")

    expect(transport.existing(package([]))).to eq([])
  end

  it "raises Unreachable when ssh does not get through, and reports other failures" do
    stub_rsync(code: 255, err: "ssh: connect to host mirror.example port 2222: Connection refused")
    expect { transport.deliver(package([])) }.to raise_error(WarpEngine::Sync::Transport::Unreachable, /Connection refused/)

    stub_rsync(code: 11, err: "rsync: mkdir failed: Permission denied")
    expect(transport.deliver(package([]))).to have_attributes(status: "failed", code: 11, message: "rsync: mkdir failed: Permission denied")
  end

  it "says when rsync is not installed" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect(transport.check).to have_attributes(ok: false, message: "rsync is not installed on this host")
    expect(transport.deliver(package([]))).to have_attributes(status: "failed", message: "rsync is not installed on this host")
  end

  it "checks by listing the base folder" do
    stub_rsync
    expect(transport.check).to have_attributes(ok: true, message: "warp@mirror.example answers and takes the key")

    stub_rsync(code: 5, err: "Permission denied (publickey).")
    expect(transport.check).to have_attributes(ok: false, status: 5, message: "Permission denied (publickey).")
  end
end
