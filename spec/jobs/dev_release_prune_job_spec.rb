require "rails_helper"

RSpec.describe WarpEngine::DevReleasePruneJob do
  it "prunes for real with the configured settings" do
    service = instance_double(WarpEngine::DevReleaseService)
    allow(WarpEngine::DevReleaseService).to receive(:new).and_return(service)
    allow(service).to receive(:prune).and_return(WarpEngine::DevReleaseService::Report.new([ "rabbit dev-1.0.0-spike: stale" ], 1))
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(service).to have_received(:prune).with(dry_run: false)
    expect(Rails.logger).to have_received(:info).with(/development build removed: rabbit dev-1.0.0-spike/)
  end
end
