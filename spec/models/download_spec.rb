require "rails_helper"

RSpec.describe WarpEngine::Download, type: :model do
  it { should validate_presence_of(:file_path) }
  it { should belong_to(:release).optional }
end
