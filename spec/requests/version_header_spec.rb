require "rails_helper"

RSpec.describe "the WarpEngine-Version header", type: :request do
  it "is the name the constant documents" do
    expect(WarpEngine::VERSION_HEADER).to eq("WarpEngine-Version")
  end

  it "is on a normal response" do
    create(:software)

    get "/api/software"

    expect(response).to have_http_status(:ok)
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end

  it "is on an error response" do
    get "/api/image/999999"

    expect(response).to have_http_status(:not_found)
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end

  it "is on a served file" do
    get "/file/nothing-here.zip"

    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end
end
