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

  it "keeps the newest build of a kept branch whatever its age" do
    build("dev-0.1-develop-old", 50.days.ago)
    old = build("dev-0.1.0-develop", 45.days.ago)
    newest = build("dev-0.1.1-develop", 40.days.ago)
    nested = build("dev-0.1.0-team-main", 40.days.ago)

    report = described_class.new.prune(ttl_days: 30, keep_branches: %w[develop team/main], dry_run: false)

    expect(report.lines).to contain_exactly("rabbit dev-0.1.0-develop: superseded by dev-0.1.1-develop",
                                            a_string_starting_with("rabbit dev-0.1-develop-old: not updated since"))
    expect(WarpEngine::Release.kept).to contain_exactly(newest, nested)
    expect(old.reload.deleted_at).to be_present
  end

  it "takes the age limit and the kept branches from the configuration" do
    allow(WarpEngine.config).to receive_messages(dev_release_ttl_days: 60, dev_release_keep_branches: [])
    build("dev-1.0.0-spike", 40.days.ago)

    expect(described_class.new.prune.count).to eq(0)
  end

  it "only reports in a dry run" do
    build("dev-1.0.0-spike", 40.days.ago)

    report = described_class.new.prune(ttl_days: 30)

    expect(report.count).to eq(1)
    expect(WarpEngine::Release.kept.count).to eq(1)
    expect(Dir.exist?(File.join(tmpdir, "rabbit", "dev-1.0.0-spike"))).to be(true)
  end
end
