require "rails_helper"
require "tmpdir"

RSpec.describe "Assembly64 outlet", type: :request do
  let(:container) { Dir.mktmpdir }
  let(:definition) do
    { key: "assembly64", type: "assembly64", platforms: %w[c64], hosts: %w[a64.example.org], repo: "ttg",
      repo_name: "Teletype Games", categories: { utility: "tools" } }
  end
  let(:firmware_headers) do
    { "Host" => "a64.example.org", "Client-Id" => "Ultimate", "User-Agent" => "Assembly Query", "Accept-Encoding" => "identity" }
  end

  before do
    allow(WarpEngine.config).to receive_messages(file_container_path: container, outlets: [ definition ])
    allow(WarpEngine::Outlets).to receive(:refresh)
    WarpEngine::SoftwareStatus.seed_defaults!
  end

  after do
    FileUtils.rm_rf(container)
    WarpEngine::AccessPolicy.reset!
  end

  def publish(name, version, title: name.titleize, platform: "c64", content: "#{name}-#{version}", at: Time.utc(2026, 11, 1), **attributes)
    software = WarpEngine::Software.find_by(name: name) ||
               create(:software, name: name, title: title, platform: platform, status: "released", **attributes)
    path = File.join(container, "#{name}-#{version}.prg")
    File.binwrite(path, content)
    release = create(:release, software: software, version: version, created_at: at)
    WarpEngine::ReleaseAsset.create!(release: release, kind: "cartridge", path: path)
    software
  end

  def get_json(path, headers: firmware_headers)
    get path, headers: headers
    JSON.parse(response.body)
  end

  def search(query, page: nil)
    get_json("/leet/search/aql#{page}?query=#{ERB::Util.url_encode(query)}")
  end

  it "walks the firmware's way: presets, search, entries, file" do
    ariadne = publish("ariadne", "1.1.0", title: "Thread of Ariadne", author: "Teletype Games", category: "game",
                                          shelf_name: "ARIADNE", content: "PRGDATA")
    publish("rabbit", "1.0.0", category: "utility", at: Time.utc(2025, 3, 5))
    publish("tetris", "1.0.0", platform: "tic80")

    presets = get_json("/leet/search/aql/presets")
    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(presets.map { |preset| preset["type"] }).to eq(%w[repo category type date latest sort order])
    expect(presets[0]["values"]).to eq([ { "aqlKey" => "ttg", "name" => "Teletype Games" } ])
    expect(presets[1]["values"]).to eq([ { "aqlKey" => "games", "name" => "Games" }, { "aqlKey" => "tools", "name" => "Tools" } ])
    expect(presets[2]["values"]).to eq([ { "aqlKey" => "prg" } ])
    expect(presets[3]["values"]).to eq([ { "aqlKey" => "2025" }, { "aqlKey" => "2026" } ])

    results = search('(name:"ariadne") & (category:games)')
    expect(results).to eq([ { "id" => ariadne.id.to_s, "name" => "Thread of Ariadne", "group" => "Teletype Games",
                              "year" => 2026, "category" => 0, "updated" => "2026-11-01 00:00:00", "type" => "prg" } ])

    entries = get_json("/leet/search/entries/#{ariadne.id}/0")
    expect(entries).to eq("contentEntry" => [ { "path" => "ARIADNE.PRG", "id" => 0, "size" => 7,
                                                "date" => Time.utc(2026, 11, 1).to_i * 1000 } ])

    expect { get "/leet/search/bin/#{ariadne.id}/0/ARIADNE.PRG", headers: firmware_headers }
      .to change(WarpEngine::Download, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("PRGDATA")
    expect(response.headers["Content-Type"]).to eq("application/octet-stream")
    expect(response.headers["Content-Disposition"]).to include('filename="ARIADNE.PRG"')
  end

  it "filters by group, type, year, repo and latest, and orders by sort and order" do
    publish("alpha", "1.0.0", author: "Zed", at: Time.utc(2025, 1, 1))
    publish("beta", "1.0.0", author: "Amy", at: 1.day.ago)

    expect(search('(group:"am")').map { |row| row["name"] }).to eq(%w[Beta])
    expect(search("(type:prg) & (date:2025)").map { |row| row["name"] }).to eq(%w[Alpha])
    expect(search("(repo:csdb)")).to eq([])
    expect(search("(latest:1week)").map { |row| row["name"] }).to eq(%w[Beta])
    expect(search("(sort:group) & (order:desc)").map { |row| row["name"] }).to eq(%w[Alpha Beta])
    expect(search("").map { |row| row["name"] }).to eq(%w[Alpha Beta])
  end

  it "finds nothing for a condition no title here can meet" do
    publish("alpha", "1.0.0")

    expect(search('(handle:"Nifty")')).to eq([])
    expect(search("(rating:>=3)")).to eq([])
  end

  it "pages a search, capped at max_results" do
    definition[:max_results] = 2
    %w[a b c].each { |name| publish("title#{name}", "1.0.0") }

    expect(search("", page: "/0/100").map { |row| row["name"] }).to eq(%w[Titlea Titleb])
    expect(search("", page: "/2/100").map { |row| row["name"] }).to eq(%w[Titlec])
    expect(search("", page: "/9/100")).to eq([])
  end

  it "keeps an unpaged search under the firmware's 16 KiB" do
    definition[:max_results] = 500
    120.times { |n| publish(format("title%03d", n), "1.0.0", title: "#{'Long title ' * 10}#{n}", author: "A" * 40) }

    get "/leet/search/aql?query=", headers: firmware_headers

    expect(response.body.bytesize).to be <= WarpEngine::Outlets::Assembly64::LEGACY_BODY_LIMIT
    expect(JSON.parse(response.body).size).to be_between(1, 119)
  end

  it "answers 404 for a title or file that is not on offer" do
    software = publish("alpha", "1.0.0")

    get "/leet/search/entries/999999/0", headers: firmware_headers
    expect(response).to have_http_status(:not_found)
    get "/leet/search/entries/abc/0", headers: firmware_headers
    expect(response).to have_http_status(:not_found)
    get "/leet/search/bin/#{software.id}/0/OTHER.PRG", headers: firmware_headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "does not answer another host" do
    publish("alpha", "1.0.0")

    get "/leet/search/aql/presets", headers: firmware_headers.merge("Host" => "www.example.org")

    expect(response).to have_http_status(:not_found)
  end

  it "answers any host when it names none" do
    definition.delete(:hosts)

    get "/leet/search/aql/presets", headers: firmware_headers.merge("Host" => "www.example.org")

    expect(response).to have_http_status(:ok)
  end

  it "answers 404 when no outlet is configured" do
    allow(WarpEngine.config).to receive(:outlets).and_return([])

    get "/leet/search/aql/presets", headers: firmware_headers

    expect(response).to have_http_status(:not_found)
  end

  it "refuses a client it does not accept, as Assembly64 does" do
    definition[:client_ids] = %w[Spiffy]

    expect(get_json("/leet/search/aql/presets")).to include("errorCode" => 464)
    expect(response).to have_http_status(:forbidden)

    get_json("/leet/search/aql/presets", headers: firmware_headers.merge("Client-Id" => "Spiffy"))
    expect(response).to have_http_status(:ok)
  end

  it "leaves out a gated title" do
    software = publish("alpha", "1.0.0")
    allow(WarpEngine.access_policy).to receive(:access_for).and_return(WarpEngine::Access.new(gated: true, entitled: false))

    expect(search("")).to eq([])
    get "/leet/search/bin/#{software.id}/0/ALPHA.PRG", headers: firmware_headers
    expect(response).to have_http_status(:not_found)
  end
end
