require "rails_helper"

RSpec.describe WarpEngine::PipelineService do
  let(:ci) { instance_double(WarpEngine::CI::Woodpecker::Adapter) }
  let(:service) { described_class.new(ci: ci) }

  def ci_run(number:, status: "success", created_at: nil)
    WarpEngine::CI::Run.new(number: number, status: status, created_at: created_at)
  end

  describe "#trigger" do
    it "delegates to client" do
      repo = build(:pipeline, repo_owner: "org", repo_name: "game")
      allow(ci).to receive(:trigger).and_return(ci_run(number: 6, status: "pending"))

      result = service.trigger(repo, branch: "main")

      expect(result.number).to eq(6)
      expect(ci).to have_received(:trigger).with(repo.remote_repo_id, branch: "main")
    end
  end

  describe "#runs" do
    it "returns the runs and refreshes the repo's cached last run" do
      repo = create(:pipeline, repo_owner: "org", repo_name: "game")
      runs = [
        ci_run(number: 2, status: "failure", created_at: Time.zone.at(1_754_500_000)),
        ci_run(number: 1, status: "success", created_at: Time.zone.at(1_754_400_000))
      ]
      allow(ci).to receive(:runs).with(repo.remote_repo_id, page: 1).and_return(runs)

      expect(service.runs(repo)).to eq(runs)

      repo.reload
      expect(repo.last_pipeline_status).to eq("failure")
      expect(repo.last_pipeline_at).to eq(Time.zone.at(1_754_500_000))
    end

    it "does not touch the cache on later pages" do
      repo = create(:pipeline, repo_owner: "org", repo_name: "game",
                    last_pipeline_status: "success")
      allow(ci).to receive(:runs).with(repo.remote_repo_id, page: 2)
        .and_return([ ci_run(number: 1, status: "failure", created_at: Time.zone.at(1_754_400_000)) ])

      service.runs(repo, page: 2)

      expect(repo.reload.last_pipeline_status).to eq("success")
    end

    it "leaves the cache alone when the repo has no runs" do
      repo = create(:pipeline, repo_owner: "org", repo_name: "game",
                    last_pipeline_status: "success")
      allow(ci).to receive(:runs).and_return([])

      expect(service.runs(repo)).to eq([])
      expect(repo.reload.last_pipeline_status).to eq("success")
    end
  end
end
