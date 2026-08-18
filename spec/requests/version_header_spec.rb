require "rails_helper"

# Every response the engine serves carries the version that served it, so a client can
# branch on the engine's age without asking a separate endpoint for it.
RSpec.describe "the WarpEngine-Version header", type: :request do
  it "is on a normal response" do
    create(:software)

    get "/api/software"

    expect(response).to have_http_status(:ok)
    expect(response.headers["WarpEngine-Version"]).to eq(WarpEngine::VERSION)
  end

  # The one a client needs most: something came back wrong, and it wants to know whether
  # the engine on the other end is old enough to explain it. `rescue_from` never reaches
  # an after_action, which is why the header is set before the action runs.
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
