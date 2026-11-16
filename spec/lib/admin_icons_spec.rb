require "rails_helper"

RSpec.describe WarpEngine::AdminIcons do
  it "draws an icon as inline SVG in the current color, hidden when decorative" do
    svg = described_class.svg(:trash)

    expect(svg).to be_html_safe
    expect(svg).to include('stroke="currentColor"', 'aria-hidden="true"', 'width="16"')
    expect(svg.scan("<path").size).to eq(5)
  end

  it "names an announced icon" do
    expect(described_class.svg(:download, label: "Get <it>", size: 20)).to include('role="img"', 'aria-label="Get &lt;it&gt;"', 'width="20"')
  end

  it "refuses an unknown icon" do
    expect { described_class.svg(:unicorn) }.to raise_error(KeyError)
  end

  it "has an icon for every file kind and every SysInfo status and group" do
    names = WarpEngine::FileIcon::BY_EXTENSION.values + [ WarpEngine::FileIcon::DEFAULT, WarpEngine::FileIcon::DIRECTORY ] +
            WarpEngine::SysInfo::STATUSES.map(&:to_sym) + WarpEngine::SysInfo.new(live: false).tree.map(&:icon)

    expect(names - described_class::PATHS.keys).to eq([])
    expect(WarpEngine::FileIcon.for("ARIADNE.PRG")).to eq(:gamepad)
    expect(WarpEngine::FileIcon.svg("x", directory: true)).to include("fm-file-icon")
  end
end
