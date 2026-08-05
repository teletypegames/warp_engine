# TestOwner exists only in the dummy app — host-side usage must override the
# owner (e.g. owner: create(:admin_user)).
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
