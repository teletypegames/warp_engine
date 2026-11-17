require "rails_helper"

RSpec.describe WarpEngine::DevReleaseService do
  let(:tmpdir) { Dir.mktmpdir }
  let(:software) { create(:software, name: "rabbit", platform: "c64") }

  before { allow(WarpEngine.config).to receive(:file_container_path).and_return(tmpdir) }
  after { FileUtils.rm_rf(tmpdir) }

  def build(version, updated)
    release = create(:release, software: software, version: version)
    release.update_columns(updated_at: updated)
    FileUtils.mkdir_p(File.join(tmpdir, "rabbit", version))
    release
  end

  it "removes superseded and stale development builds, folders included, and nothing else" do
    stable = build("1.2.0", 90.days.ago)
    old_feature = build("dev-1.2.0-feature", 5.days.ago)
    feature = build("dev-1.3.0-feature", 1.day.ago)
    stale = build("dev-1.0.0-spike", 40.days.ago)

    report = described_class.new.prune(ttl_days: 30, dry_run: false)

    expect(report.count).to eq(2)
    expect(report.lines).to contain_exactly("rabbit dev-1.2.0-feature: superseded by dev-1.3.0-feature",
                                            a_string_starting_with("rabbit dev-1.0.0-spike: not updated since"))
    expect(WarpEngine::Release.kept).to contain_exactly(stable, feature)
    expect(old_feature.reload.deleted_at).to be_present
    expect(Dir.exist?(File.join(tmpdir, "rabbit", "dev-1.2.0-feature"))).to be(false)
    expect(Dir.exist?(File.join(tmpdir, "rabbit", "dev-1.0.0-spike"))).to be(false)
    expect(Dir.exist?(File.join(tmpdir, "rabbit", "1.2.0"))).to be(true)
    expect(stale.reload.deleted_at).to be_present
  end

  it "only reports in a dry run" do
    build("dev-1.0.0-spike", 40.days.ago)

    report = described_class.new.prune(ttl_days: 30)

    expect(report.count).to eq(1)
    expect(WarpEngine::Release.kept.count).to eq(1)
    expect(Dir.exist?(File.join(tmpdir, "rabbit", "dev-1.0.0-spike"))).to be(true)
  end
end
