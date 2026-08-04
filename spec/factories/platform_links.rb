FactoryBot.define do
  factory :platform_link, class: "WarpEngine::PlatformLink" do
    sequence(:name) { |n| "Link #{n}" }
    platform { "tic80" }
    url { "https://example.com/link" }
    position { 0 }
  end
end
