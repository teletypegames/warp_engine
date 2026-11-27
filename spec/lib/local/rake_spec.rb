require "rails_helper"
require "rake"
require "webmock/rspec"
require_relative "../../support/local_helpers"

RSpec.describe "warp_engine:local rake tasks" do
  include LocalHelpers

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "warp_engine:local:enable" }
  end

  def invoke(name, *args)
    task = Rake::Task[name]
    task.reenable
    expect { task.invoke(*args) }
  end

  it "starts a provider and prints its steps, then lists the state and the sign-in" do
    stub_gitea_bootstrap

    invoke("warp_engine:local:enable", "gitea").to output(/create the organisation games.*Git server \(Gitea\) is ready/m).to_stdout
    invoke("warp_engine:local:status").to output(/gitea\s+scm\s+ready/).to_stdout
    invoke("warp_engine:local:credentials", "gitea").to output(/URL=http:\/\/localhost:7471\nUSER=warp-admin\nPASSWORD=\h{32}/).to_stdout
  end

  it "stops on an unknown provider" do
    invoke("warp_engine:local:enable", "jenkins").to raise_error(SystemExit).and output(/No local provider "jenkins"/).to_stderr
  end
end
