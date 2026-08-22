FactoryBot.define do
  factory :image, class: "Image" do
    sequence(:filename) { |n| "image-#{n}.png" }
    original_filename { "image.png" }
    content_type { "image/png" }
  end
end
