FactoryBot.define do
  factory :release, class: "WarpEngine::Release" do
    software
    sequence(:version) { |n| "1.0.#{n}" }
  end
end
