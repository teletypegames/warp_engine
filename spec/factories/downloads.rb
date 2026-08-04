FactoryBot.define do
  factory :download, class: "WarpEngine::Download" do
    file_path { "/test/file.tic" }
    ip_address { "127.0.0.1" }
  end
end
