FactoryBot.define do
  factory :test_owner, class: "TestOwner" do
    name { "test owner" }
  end

  factory :application_token, class: "WarpEngine::ApplicationToken" do
    name { "CI token" }
    scopes { [ "update" ] }
    association :owner, factory: :test_owner

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :unrestricted do
      unrestricted { true }
    end
  end
end
