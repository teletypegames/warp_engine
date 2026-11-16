require "rails_helper"
require "webmock/rspec"

RSpec.describe "CI adapter ping" do
  it "answers with the token user when Woodpecker takes the token" do
    stub_request(:get, "https://ci.example/api/user").to_return(status: 200, body: { login: "mr.zero" }.to_json)
    adapter = WarpEngine::CI::Woodpecker::Adapter.new(url: "https://ci.example", api_token: "tok", repo_owner: "games")

    ping = adapter.ping

    expect(ping).to be_ok
    expect(ping.detail).to eq("answers as mr.zero")
    expect(ping.ms).to be_a(Integer)
  end

  it "reports a refused token without raising" do
    stub_request(:get, "https://gitlab.example/api/v4/user").to_return(status: 401, body: "{}")
    adapter = WarpEngine::CI::Gitlab::Adapter.new(url: "https://gitlab.example", api_token: "tok")

    ping = adapter.ping

    expect(ping).not_to be_ok
    expect(ping.detail).to include("401")
  end

  it "has nothing to ask without CI" do
    expect(WarpEngine::CI::Null.new.ping).to be_nil
  end
end
