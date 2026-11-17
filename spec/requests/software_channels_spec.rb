require "rails_helper"

RSpec.describe "GET /api/software channels", type: :request do
  let(:software) { create(:software, name: "rabbit", platform: "c64", status: "released") }

  before do
    create(:release, software: software, version: "1.2.0", created_at: 3.days.ago)
    create(:release, software: software, version: "1.3.0-beta.1", created_at: 2.days.ago)
    create(:release, software: software, version: "dev-1.3.0-feature", created_at: 1.day.ago)
  end

  def entry(params = {})
    get "/api/software", params: params
    JSON.parse(response.body)["softwares"].find { |sw| sw.dig("software", "name") == "rabbit" }
  end

  it "lists the stable and beta releases with their channel, never a dev build, and offers the stable one" do
    rabbit = entry
    expect(rabbit["releases"].map { |r| [ r["version"], r["channel"] ] }).to eq([ %w[1.3.0-beta.1 beta], %w[1.2.0 stable] ])
    expect(rabbit["latestRelease"]["version"]).to eq("1.2.0")
  end

  it "offers the newer pre-release to a caller asking for beta" do
    expect(entry(channel: "beta")["latestRelease"]["version"]).to eq("1.3.0-beta.1")
  end
end
