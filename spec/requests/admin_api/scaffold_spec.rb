require "rails_helper"

RSpec.describe "Admin API scaffold", type: :request do
  include AdminApiHelpers

  let(:repo) do
    WarpEngine::Scm::Repo.new(id: 9, owner: "games", name: "rabbit", html_url: "https://git.example/games/rabbit",
                                clone_url: "https://git.example/games/rabbit.git", ssh_url: "ssh://git@git.example/games/rabbit.git")
  end
  let(:scm) { instance_double(WarpEngine::Scm::Gitea, configured?: true, create_repo: repo) }

  before do
    allow(WarpEngine).to receive(:scm).and_return(scm)
    allow(WarpEngine).to receive(:ci).and_return(WarpEngine::CI::Null.new)
  end

  it "starts a software owned by the caller and answers what it made" do
    api_post("/softwares/scaffold", { name: "rabbit", title: "Rabbit", platform: "c64" })

    expect(response).to have_http_status(:created)
    expect(json["data"]).to include("repository" => include("sshUrl" => repo.ssh_url), "ciRepositoryId" => nil,
                                    "warnings" => [ "no CI is configured: the repository builds nothing yet" ])
    expect(WarpEngine::Software.find_by(name: "rabbit").owner).to eq(admin_owner)
  end

  it "answers 409 for a taken name" do
    create(:software, name: "rabbit")

    api_post("/softwares/scaffold", { name: "rabbit", title: "Rabbit", platform: "c64" })

    expect(response).to have_http_status(:conflict)
  end

  it "needs the write scope" do
    api_post("/softwares/scaffold", { name: "rabbit", title: "Rabbit", platform: "c64" }, token: admin_token_with("admin:read"))

    expect(response).to have_http_status(:forbidden)
  end
end
