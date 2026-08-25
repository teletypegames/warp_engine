require "rails_helper"
require "webmock/rspec"

RSpec.describe WarpEngine::CI::Woodpecker::Client do
  let(:base_url) { "https://ci.example.test" }
  let(:token) { "wp-test-token" }
  let(:client) { described_class.new(url: base_url, token: token) }

  def stub_wp(method, path, status: 200, body: nil, request_body: nil)
    stub = stub_request(method, "#{base_url}#{path}")
      .with(headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" })
    stub = stub.with(body: request_body) if request_body
    stub.to_return(status: status, body: body&.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "repos" do
    it "lists repos" do
      repos = [ { "id" => 1, "name" => "game1" } ]
      stub_wp(:get, "/api/repos", body: repos)

      expect(client.list_repos).to eq(repos)
    end

    it "gets a repo" do
      repo = { "id" => 42, "name" => "mygame" }
      stub_wp(:get, "/api/repos/42", body: repo)

      expect(client.get_repo(42)).to eq(repo)
    end

    it "deactivates a repo" do
      stub_wp(:delete, "/api/repos/42", status: 204)

      expect(client.deactivate_repo(42)).to be_nil
    end
  end

  describe "secrets" do
    it "lists secrets" do
      secrets = [ { "name" => "application_token" } ]
      stub_wp(:get, "/api/repos/1/secrets", body: secrets)

      expect(client.list_secrets(1)).to eq(secrets)
    end

    it "creates a secret" do
      stub_wp(:post, "/api/repos/1/secrets", status: 200, body: { "name" => "application_token" })

      result = client.create_secret(1, name: "application_token", value: "secret123")
      expect(result["name"]).to eq("application_token")
    end

    it "updates a secret" do
      stub_wp(:patch, "/api/repos/1/secrets/application_token", status: 200, body: { "name" => "application_token" })

      result = client.update_secret(1, "application_token", value: "newsecret")
      expect(result["name"]).to eq("application_token")
    end

    it "deletes a secret" do
      stub_wp(:delete, "/api/repos/1/secrets/application_token", status: 204)

      expect(client.delete_secret(1, "application_token")).to be_nil
    end
  end

  describe "pipelines" do
    it "lists pipelines" do
      pipelines = [ { "number" => 1, "status" => "success" } ]
      stub_wp(:get, "/api/repos/42/pipelines?page=1&perPage=25", body: pipelines)

      expect(client.list_pipelines(42)).to eq(pipelines)
    end

    it "gets latest pipeline" do
      pipeline = { "number" => 5, "status" => "running" }
      stub_wp(:get, "/api/repos/42/pipelines/latest", body: pipeline)

      expect(client.latest_pipeline(42)).to eq(pipeline)
    end

    it "triggers a pipeline" do
      pipeline = { "number" => 6, "status" => "pending" }
      stub_wp(:post, "/api/repos/42/pipelines", body: pipeline)

      expect(client.trigger_pipeline(42, branch: "main")).to eq(pipeline)
    end
  end

  describe "error handling" do
    it "raises ApiError on 404" do
      stub_wp(:get, "/api/repos/999", status: 404, body: { "error" => "not found" })

      expect { client.get_repo(999) }.to raise_error(WarpEngine::CI::ApiError) { |e|
        expect(e.status).to eq(404)
      }
    end

    it "raises ApiError on 500" do
      stub_wp(:get, "/api/repos", status: 500, body: { "error" => "internal" })

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ApiError) { |e|
        expect(e.status).to eq(500)
      }
    end

    it "raises ConnectionError on connection refused" do
      stub_request(:get, "#{base_url}/api/repos").to_raise(Errno::ECONNREFUSED)

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ConnectionError)
    end

    it "raises ConnectionError on timeout" do
      stub_request(:get, "#{base_url}/api/repos").to_timeout

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ConnectionError)
    end

    it "raises ApiError when a 200 response is not JSON" do
      stub_request(:get, "#{base_url}/api/repos")
        .to_return(status: 200, body: "<!doctype html><html></html>",
                   headers: { "Content-Type" => "text/html" })

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ApiError, /Expected JSON/)
    end
  end
end
