require "rails_helper"
require "webmock/rspec"

RSpec.describe WarpEngine::CI::Gitlab::Client do
  let(:base_url) { "https://gitlab.example.test" }
  let(:token) { "gl-test-token" }
  let(:client) { described_class.new(url: base_url, token: token) }

  def stub_gl(method, path, status: 200, body: nil, request_body: nil)
    stub = stub_request(method, "#{base_url}#{path}")
      .with(headers: { "PRIVATE-TOKEN" => token, "Accept" => "application/json" })
    stub = stub.with(body: request_body) if request_body
    stub.to_return(status: status, body: body&.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "repos" do
    it "lists repos" do
      repos = [ { "id" => 1, "path" => "game1" } ]
      stub_gl(:get, "/api/v4/projects?membership=true&per_page=100&simple=true", body: repos)

      expect(client.list_repos).to eq(repos)
    end

    it "gets a repo" do
      repo = { "id" => 42, "path" => "mygame" }
      stub_gl(:get, "/api/v4/projects/42", body: repo)

      expect(client.get_repo(42)).to eq(repo)
    end

    it "activate is a no-op" do
      expect(client.activate_repo(42)).to be_nil
    end

    it "deactivate is a no-op" do
      expect(client.deactivate_repo(42)).to be_nil
    end
  end

  describe "secrets (variables)" do
    it "lists variables" do
      vars = [ { "key" => "application_token" } ]
      stub_gl(:get, "/api/v4/projects/1/variables", body: vars)

      expect(client.list_secrets(1)).to eq(vars)
    end

    it "creates a variable" do
      stub_gl(:post, "/api/v4/projects/1/variables", status: 201, body: { "key" => "application_token" })

      result = client.create_secret(1, name: "application_token", value: "secret123")
      expect(result["key"]).to eq("application_token")
    end

    it "updates a variable" do
      stub_gl(:put, "/api/v4/projects/1/variables/application_token", status: 200, body: { "key" => "application_token" })

      result = client.update_secret(1, "application_token", value: "newsecret")
      expect(result["key"]).to eq("application_token")
    end

    it "deletes a variable" do
      stub_gl(:delete, "/api/v4/projects/1/variables/application_token", status: 204)

      expect(client.delete_secret(1, "application_token")).to be_nil
    end
  end

  describe "pipelines" do
    it "lists pipelines" do
      pipelines = [ { "id" => 1, "status" => "success" } ]
      stub_gl(:get, "/api/v4/projects/42/pipelines?page=1&per_page=25", body: pipelines)

      expect(client.list_pipelines(42)).to eq(pipelines)
    end

    it "gets latest pipeline" do
      pipeline = { "id" => 5, "status" => "running" }
      stub_gl(:get, "/api/v4/projects/42/pipelines?per_page=1&sort=desc", body: [ pipeline ])

      expect(client.latest_pipeline(42)).to eq(pipeline)
    end

    it "returns nil when no pipelines exist" do
      stub_gl(:get, "/api/v4/projects/42/pipelines?per_page=1&sort=desc", body: [])

      expect(client.latest_pipeline(42)).to be_nil
    end

    it "gets a specific pipeline" do
      pipeline = { "id" => 99, "status" => "success" }
      stub_gl(:get, "/api/v4/projects/42/pipelines/99", body: pipeline)

      expect(client.get_pipeline(42, 99)).to eq(pipeline)
    end

    it "triggers a pipeline" do
      pipeline = { "id" => 6, "status" => "created" }
      stub_gl(:post, "/api/v4/projects/42/pipeline", body: pipeline)

      expect(client.trigger_pipeline(42, branch: "main")).to eq(pipeline)
    end
  end

  describe "error handling" do
    it "raises ApiError on 404" do
      stub_gl(:get, "/api/v4/projects/999", status: 404, body: { "error" => "not found" })

      expect { client.get_repo(999) }.to raise_error(WarpEngine::CI::ApiError) { |e|
        expect(e.status).to eq(404)
      }
    end

    it "raises ApiError on 500" do
      stub_gl(:get, "/api/v4/projects?membership=true&per_page=100&simple=true", status: 500, body: { "error" => "internal" })

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ApiError) { |e|
        expect(e.status).to eq(500)
      }
    end

    it "raises ConnectionError on connection refused" do
      stub_request(:get, "#{base_url}/api/v4/projects?membership=true&per_page=100&simple=true").to_raise(Errno::ECONNREFUSED)

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ConnectionError)
    end

    it "raises ConnectionError on timeout" do
      stub_request(:get, "#{base_url}/api/v4/projects?membership=true&per_page=100&simple=true").to_timeout

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ConnectionError)
    end

    it "raises ApiError when a 200 response is not JSON" do
      stub_request(:get, "#{base_url}/api/v4/projects?membership=true&per_page=100&simple=true")
        .to_return(status: 200, body: "<!doctype html><html></html>",
                   headers: { "Content-Type" => "text/html" })

      expect { client.list_repos }.to raise_error(WarpEngine::CI::ApiError, /Expected JSON/)
    end
  end
end
