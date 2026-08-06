FactoryBot.define do
  factory :pipeline, class: "WarpEngine::Pipeline" do
    sequence(:woodpecker_repo_id) { |n| n }
    repo_owner { "testorg" }
    sequence(:repo_name) { |n| "game-#{n}" }
    platform { "tic80" }
    active { true }

    trait :with_software do
      association :software
    end

    trait :inactive do
      active { false }
    end
  end
end
