require "rails_helper"

RSpec.describe WarpEngine::DownloadStatsService do
  subject(:service) { described_class.new }

  let(:software) { create(:software, name: "ra", title: "Ra") }
  let(:release) { create(:release, software: software, version: "1.0") }

  before do
    create(:download, file_path: "a.tic", release: release)
    create(:download, file_path: "a.tic", release: release, created_at: 10.days.ago)
    create(:download, file_path: "b.zip", created_at: 2.months.ago)
  end

  it "counts in total and by period" do
    expect(service.summary).to eq(total: 3, today: 1, week: 1, month: 2)
  end

  it "ranks files and softwares" do
    expect(service.top_files(limit: 1)).to match([ hash_including(file_path: "a.tic", downloads: 2) ])
    expect(service.top_softwares).to eq([ { software_id: software.id, name: "ra", title: "Ra", downloads: 2 } ])
  end

  it "breaks one software down by release and file" do
    stats = service.for_software(software)

    expect(stats[:total]).to eq(2)
    expect(stats[:releases]).to match([ hash_including(version: "1.0", downloads: 2, files: [ hash_including(file_path: "a.tic") ]) ])
  end
end
