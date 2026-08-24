require "rails_helper"

RSpec.describe WarpEngine::CI::Gitlab::SignatureVerifier do
  let(:webhook_secret) { "gl-webhook-secret-token" }

  def mock_request(token:)
    instance_double(ActionDispatch::Request,
                    headers: { "X-Gitlab-Token" => token })
  end

  it "accepts a request with matching token" do
    request = mock_request(token: webhook_secret)
    verifier = described_class.new(request, webhook_secret: webhook_secret)

    expect(verifier).to be_valid
  end

  it "rejects a request with wrong token" do
    request = mock_request(token: "wrong-token")
    verifier = described_class.new(request, webhook_secret: webhook_secret)

    expect(verifier).not_to be_valid
  end

  it "rejects a request with no token" do
    request = mock_request(token: nil)
    verifier = described_class.new(request, webhook_secret: webhook_secret)

    expect(verifier).not_to be_valid
  end

  it "rejects a request with blank token" do
    request = mock_request(token: "")
    verifier = described_class.new(request, webhook_secret: webhook_secret)

    expect(verifier).not_to be_valid
  end

  it "rejects when webhook secret is not configured" do
    request = mock_request(token: "anything")
    verifier = described_class.new(request, webhook_secret: nil)

    expect(verifier).not_to be_valid
  end
end
