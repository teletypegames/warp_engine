require "rails_helper"

RSpec.describe "Build check endpoint", type: :request do
  def check(body)
    post "/build/check", params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    JSON.parse(response.body)
  end

  it "passes metadata a publish would take" do
    json = check(platform: "c64", version: "1.0.0", kinds: %w[cartridge win_x64],
                 metadata: { name: "rabbit", title: "Rabbit", web: { runtime: "emulatorjs" } })

    expect(json).to eq("ok" => true, "problems" => [])
  end

  it "names every problem the publish would hit" do
    software = create(:software, name: "rabbit", platform: "c64")
    create(:release, software: software, version: "2.0.0")
    create(:software, name: "other", platform: "c64", shelf_name: "RABBIT")

    json = check(platform: "c64", version: "1.5.0", kinds: %w[html],
                 metadata: { name: "rabbit", shelf_name: "rabbit", colour: "red",
                             web: { runtime: "dosbox", params: {} } })

    expect(json["ok"]).to be(false)
    messages = json["problems"].to_h { |problem| [ problem["field"], problem["message"] ] }
    expect(messages).to include("title" => "title is missing", "colour" => "colour is not read by a publish",
                                "shelf_name" => "RABBIT is taken on the C64 shelf",
                                "version" => "rabbit 1.5.0 is older than 2.0.0, which is published already",
                                "web" => "C64 has no web runtime dosbox")
    expect(json["problems"].select { |problem| problem["field"] == "kinds" }.map { |problem| problem["message"] })
      .to contain_exactly("cartridge is required and not built", "C64 does not publish html")
  end

  it "warns of a runtime parameter the runtime does not take" do
    json = check(platform: "c64", metadata: { name: "rabbit", title: "Rabbit", web: { params: { speed: "2" } } })

    expect(json["ok"]).to be(true)
    expect(json["problems"]).to eq([ { "field" => "web", "message" => "emulatorjs takes no parameter speed", "level" => "warning" } ])
  end

  it "answers an unknown platform" do
    expect(check(platform: "amiga", metadata: {})["problems"].first["field"]).to eq("platform")
  end
end
