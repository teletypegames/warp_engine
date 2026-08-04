FactoryBot.define do
  factory :software, class: "WarpEngine::Software" do
    sequence(:name) { |n| "game-#{n}" }
    title { "Test Game" }
    author { "dev" }
    platform { "tic80" }
    status { "development" }
  end
end
