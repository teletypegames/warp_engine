require "rails_helper"

RSpec.describe "GET /api/stores", type: :request do
  after { WarpEngine::StoreRegistry.reset! }

  def stores
    get "/api/stores"
    JSON.parse(response.body)
  end

  it "lists this catalog alone by default, named by its host" do
    expect(stores).to eq([ { "name" => "www.example.com", "catalogUrl" => "http://www.example.com" } ])
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end

  it "names this catalog by store_name" do
    allow(WarpEngine.config).to receive(:store_name).and_return("My Studio")

    expect(stores).to eq([ { "name" => "My Studio", "catalogUrl" => "http://www.example.com" } ])
  end

  it "serves a fixed list in its order, with this catalog where :own stands" do
    allow(WarpEngine.config).to receive_messages(
      store_name: "My Studio",
      store_registry: [ { name: "Friends", catalog_url: "https://friends.example" }, :own ]
    )

    expect(stores).to eq([ { "name" => "Friends", "catalogUrl" => "https://friends.example" },
                           { "name" => "My Studio", "catalogUrl" => "http://www.example.com" } ])
  end

  it "asks a host adapter and leaves out what is not a store" do
    adapter = Class.new do
      def stores(catalog_url:)
        [ { "name" => "Apex", "catalogUrl" => "https://apex.example" },
          WarpEngine::StoreRegistry::Entry.new(name: "Zed", catalog_url: "https://zed.example"),
          { name: "", catalog_url: "https://nameless.example" },
          { name: "Broken", catalog_url: "ftp://broken.example" } ]
      end
    end.new
    allow(WarpEngine.config).to receive(:store_registry).and_return(adapter)

    expect(stores.map { |store| store["name"] }).to eq(%w[Apex Zed])
  end

  it "answers 404 when the registry is off" do
    allow(WarpEngine.config).to receive(:store_registry).and_return(:none)

    get "/api/stores"

    expect(response).to have_http_status(:not_found)
  end
end
