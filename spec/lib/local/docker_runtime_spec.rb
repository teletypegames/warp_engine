require "rails_helper"
require "socket"
require "tmpdir"

RSpec.describe WarpEngine::Local::Runtime::Docker do
  let(:dir) { Dir.mktmpdir("docker", "/tmp") }
  let(:path) { File.join(dir, "d.sock") }
  let(:requests) { [] }
  let(:answers) { {} }
  let(:runtime) { described_class.new(socket: path, timeout: 5) }

  before do
    server = UNIXServer.new(path)
    @thread = Thread.new do
      loop do
        client = server.accept
        head = +""
        head << client.readpartial(65_536) until head.include?("\r\n\r\n")
        line = head.lines.first.strip
        length = head[/Content-Length: (\d+)/i, 1].to_i
        body = head.split("\r\n\r\n", 2)[1].to_s
        body << client.readpartial(65_536) while body.bytesize < length
        requests << [ line, body.empty? ? nil : JSON.parse(body) ]
        status, payload = answers.find { |pattern, _| line.match?(pattern) }&.last || [ 404, { message: "no such thing" } ]
        text = payload.is_a?(String) ? payload : payload.to_json
        client.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n" \
                     "#{text.bytesize.to_s(16)}\r\n#{text}\r\n0\r\n\r\n")
        client.close
      end
    rescue IOError
      nil
    end
  end

  after do
    @thread.kill
    FileUtils.rm_rf(dir)
  end

  let(:spec) do
    WarpEngine::Local::ContainerSpec.build(name: "warp-local-gitea", image: "gitea/gitea:1.27.3", env: { "A" => "1" },
                                           volumes: { "warp-local-gitea-data" => "/data" }, ports: { 7471 => 3000 })
  end

  it "is available when the socket is there" do
    expect(runtime.available?).to be(true)
    expect(described_class.new(socket: "/nope.sock").unavailable_reason).to include("no Docker socket")
  end

  it "creates a labelled container with its volume, port on 127.0.0.1 and network alias, then starts it" do
    answers[%r{GET /containers/warp-local-gitea/json}] = [ 404, {} ]
    answers[%r{POST /volumes/create}] = [ 201, {} ]
    answers[%r{POST /containers/create}] = [ 201, { Id: "abc" } ]
    answers[%r{POST /containers/warp-local-gitea/start}] = [ 204, "" ]

    runtime.run(spec, network: "warp-local")

    _, body = requests.find { |line, _| line.start_with?("POST /containers/create?name=warp-local-gitea") }
    expect(body["Labels"]).to include(WarpEngine::Local::LABEL => "1")
    expect(body["HostConfig"]["PortBindings"]).to eq("3000/tcp" => [ { "HostIp" => "127.0.0.1", "HostPort" => "7471" } ])
    expect(body["HostConfig"]["Binds"]).to eq([ "warp-local-gitea-data:/data" ])
    expect(body["NetworkingConfig"]["EndpointsConfig"]["warp-local"]["Aliases"]).to eq([ "warp-local-gitea" ])
    expect(requests.map(&:first)).to include(a_string_starting_with("POST /containers/warp-local-gitea/start"))
  end

  it "leaves a running container of the same spec alone" do
    created = nil
    answers[%r{POST /containers/create}] = [ 201, { Id: "abc" } ]
    answers[%r{GET /containers/warp-local-gitea/json}] = [ 404, {} ]
    answers[%r{POST /volumes/create}] = [ 201, {} ]
    answers[%r{/start}] = [ 204, "" ]
    runtime.run(spec, network: "warp-local")
    created = requests.find { |line, _| line.start_with?("POST /containers/create") }.last
    requests.clear
    answers[%r{GET /containers/warp-local-gitea/json}] = [ 200, { Config: { Image: spec.image, Labels: created["Labels"] }, State: { Running: true } } ]

    runtime.run(spec, network: "warp-local")

    expect(requests.map(&:first)).to eq([ "GET /containers/warp-local-gitea/json HTTP/1.1" ])
  end

  it "does not stop or remove a container without its label" do
    answers[%r{GET /containers/other/json}] = [ 200, { Config: { Labels: {} } } ]

    runtime.stop("other")
    runtime.remove("other")

    expect(requests.map(&:first)).to all(start_with("GET "))
  end

  it "pulls an image it does not have and reports a failed pull" do
    answers[%r{GET /images/}] = [ 404, {} ]
    answers[%r{POST /images/create}] = [ 200, %({"status":"Pulling"}\n{"error":"manifest unknown"}\n) ]

    expect { runtime.pull("gitea/gitea:1.27.3") }.to raise_error(WarpEngine::Local::Runtime::Error, /manifest unknown/)
    expect(requests.last.first).to start_with("POST /images/create?fromImage=gitea%2Fgitea&tag=1.27.3")
  end
end
