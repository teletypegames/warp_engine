require "rails_helper"
require_relative "../support/runtime_helpers"

RSpec.describe "GET /play/:name/:version", type: :request do
  let(:tmpdir) { Dir.mktmpdir }
  let(:software) { create(:software, name: "rabbit", title: "Rabbit & Co", platform: "c64", category: "game") }
  let(:runtime) do
    install_runtime_version(name: "emulatorjs", version: "4.2.3", files: { "loader.js" => "loader" },
                            components: { "core" => %w[vice_x64sc vice_x64] })
  end
  let(:release) do
    create(:release, software: software, version: "1.0.0", runtime_version: runtime, web_binding: "emulatorjs",
                     web_options: { "params" => { "options" => { "speed" => "2" } } })
  end

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    File.binwrite(File.join(tmpdir, "rabbit-1.0.0.prg"), "\x01\x08")
    release.release_assets.create!(kind: "package", path: File.join(tmpdir, "rabbit-1.0.0.prg"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "renders the runtime's page with the payload, the runtime folder and the parameters" do
    get "/play/rabbit/1.0.0"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("<title>Rabbit &amp; Co</title>", '"core":"vice_x64sc"',
                                     'const payloadUrl = await receivePayload("/file/rabbit-1.0.0.prg", true)', 'const runtimeUrl = "/file/_runtimes/emulatorjs-4.2.3/"',
                                     '"keyboardInput":"enabled"', '"speed":"2"', "EJS_threads: false")
    expect(response.headers["Cross-Origin-Embedder-Policy"]).to be_nil
  end

  it "plays the joystick from the arrows and Space, starting on it for a game" do
    get "/play/rabbit/1.0.0"

    expect(response.body).to include('"joystick":{"up":"ArrowUp","down":"ArrowDown","left":"ArrowLeft","right":"ArrowRight",' \
                                     '"fire":"Space","toggle":"F9","categories":["game"]}',
                                     'const category = "game"', 'addEventListener("keydown", onKey, true)',
                                     "EJS_VirtualGamepadSettings")
  end

  it "does not play when the software turns the web off" do
    software.update!(disabled_kinds: %w[web])

    get "/play/rabbit/1.0.0"

    expect(response).to have_http_status(:not_found)
  end

  it "plays in another binding of the platform, isolated when it says so" do
    config = WarpEngine::Configuration.new
    config.platform_web :c64, :emulatorjs, as: :fast, core: "vice_x64", isolated: true
    allow(WarpEngine).to receive(:config).and_return(config)
    allow(config).to receive(:file_container_path).and_return(tmpdir)

    get "/play/rabbit/1.0.0/fast"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"core":"vice_x64"', "EJS_threads: true")
    expect(response.headers).to include("Cross-Origin-Opener-Policy" => "same-origin", "Cross-Origin-Embedder-Policy" => "require-corp")
  end

  it "answers 404 for an unknown release or binding, an unbound release and a missing core" do
    get "/play/rabbit/9.9"
    expect(response).to have_http_status(:not_found)

    get "/play/rabbit/1.0.0/nope"
    expect(response).to have_http_status(:not_found)

    release.update!(web_binding: nil, runtime_version: nil)
    get "/play/rabbit/1.0.0"
    expect(response).to have_http_status(:not_found)

    release.update!(web_binding: "emulatorjs", runtime_version: runtime)
    runtime.runtime_components.where(key: "vice_x64sc").delete_all
    get "/play/rabbit/1.0.0"
    expect(response).to have_http_status(:not_found)
  end

  it "serves a runtime's file for a year and lists the release's players in the catalog" do
    get "/file/_runtimes/emulatorjs-4.2.3/loader.js"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"].split(", ")).to contain_exactly("public", "max-age=#{1.year.to_i}", "immutable")

    json = WarpEngine::ReleaseSerializer.render_as_hash(release.reload)
    expect(json[:playUrl]).to eq("/play/rabbit/1.0.0")
    expect(json[:players]).to eq([ { binding: "emulatorjs", runtime: "emulatorjs", label: "EmulatorJS 4.2.3",
                                     url: "/play/rabbit/1.0.0", default: true } ])
  end

  it "falls back to the html folder for a release that plays from one" do
    other = create(:release, software: software, version: "0.9")
    other.release_assets.create!(kind: "html", path: File.join(tmpdir, "rabbit-0.9"))

    json = WarpEngine::ReleaseSerializer.render_as_hash(other)
    expect(json[:playUrl]).to eq("/file/rabbit-0.9")
    expect(json[:players]).to eq([])
  end

  it "does not play a release whose metadata turned the web off, its html folder neither" do
    other = create(:release, software: software, version: "0.8", web_options: { "enabled" => false })
    other.release_assets.create!(kind: "html", path: File.join(tmpdir, "rabbit-0.8"))

    expect(WarpEngine::ReleaseSerializer.render_as_hash(other)[:playUrl]).to eq("")
  end
end

RSpec.describe "GET /play-preview/:platform", type: :request do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir)
    install_runtime_version(name: "emulatorjs", version: "4.2.3", files: { "loader.js" => "loader" },
                            components: { "core" => %w[vice_x64sc] })
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "plays a local build in the runtime a release would get, asking for the file" do
    get "/play-preview/c64", params: { payload: "message", title: "Rabbit", params: { options: { "speed" => "2" } }.to_json }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<title>Rabbit</title>", 'const payloadUrl = await receivePayload("message", true)',
                                     '"core":"vice_x64sc"', '"speed":"2"', '"warpengine.payload"',
                                     'parent.postMessage({ type: "warpengine.ready" }, "*")', "event.source !== window",
                                     'navigator.getAutoplayPolicy("audiocontext") === "allowed"')
  end

  it "passes the category a local build gives, none without it" do
    get "/play-preview/c64", params: { payload: "message", category: "tool" }
    expect(response.body).to include('const category = "tool"', '"toggle":"F9"')

    get "/play-preview/c64", params: { payload: "message" }
    expect(response.body).to include("const category = null")
  end

  it "takes the file only as a message" do
    get "/play-preview/c64", params: { payload: "http://127.0.0.1:47111/rabbit.prg" }

    expect(response).to have_http_status(:bad_request)
  end

  it "answers 404 where the platform does not play on the web" do
    get "/play-preview/godot", params: { payload: "message" }

    expect(response).to have_http_status(:not_found)
  end
end
