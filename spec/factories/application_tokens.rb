# A TestOwner csak a dummy appban létezik — host-oldali használatnál az owner-t
# felül kell írni (pl. owner: create(:admin_user)).
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
  end
end
