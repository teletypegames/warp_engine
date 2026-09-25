require "json_schemer"

module AdminApiHelpers
  ADMIN_SCOPES = %w[admin:read admin:write].freeze

  def self.included(base)
    base.let(:admin_owner) { create(:test_owner, name: "admin") }
    base.let(:admin_token) { create(:application_token, owner: admin_owner, scopes: ADMIN_SCOPES) }

    base.before do
      allow(WarpEngine.config).to receive(:application_token_owner_class).and_return("TestOwner")
      WarpEngine.config.admin_api = WarpEngine::AdminApi::Configuration.new.tap { |c| c.enabled = true }
    end

    base.after do
      WarpEngine.config.admin_api = nil
    end
  end

  def admin_config = WarpEngine.config.admin_api

  def auth(token = admin_token)
    { "Authorization" => "Bearer #{token.plain_token}" }
  end

  def admin_token_with(*scopes, **attributes)
    create(:application_token, owner: admin_owner, scopes: scopes.flatten, **attributes)
  end

  def json = JSON.parse(response.body)

  def api_get(path, token: admin_token, params: {})
    get "/api/admin/v1#{path}", params: params, headers: auth(token)
    conform!
  end

  def api_post(path, body = {}, token: admin_token)
    post "/api/admin/v1#{path}", params: body.to_json, headers: auth(token).merge("CONTENT_TYPE" => "application/json")
    conform!
  end

  def api_patch(path, body = {}, token: admin_token)
    patch "/api/admin/v1#{path}", params: body.to_json, headers: auth(token).merge("CONTENT_TYPE" => "application/json")
    conform!
  end

  def api_delete(path, token: admin_token, params: {})
    delete "/api/admin/v1#{path}", params: params, headers: auth(token)
    conform!
  end

  def openapi_document
    JSON.parse(WarpEngine::AdminApi::OpenApi.document(server_url: "http://www.example.com/api/admin/v1").to_json)
  end

  def conform!
    operation = WarpEngine::AdminApi::Registry.find(request.params["operation"])
    return if operation.nil? || response.status == 204 || !response.media_type.to_s.include?("json")

    document = openapi_document
    responses = document.dig("paths", operation.openapi_path, operation.verb.to_s, "responses")
    return if responses.nil? || !responses.key?(response.status.to_s)

    escaped = operation.openapi_path.gsub("~", "~0").gsub("/", "~1").gsub("{", "%7B").gsub("}", "%7D")
    pointer = "#/paths/#{escaped}/#{operation.verb}/responses/#{response.status}"
    target = responses[response.status.to_s]
    pointer = target["$ref"] if target["$ref"]
    schemer = JSONSchemer.openapi(document).ref("#{pointer}/content/application~1json/schema")
    errors = schemer.validate(JSON.parse(response.body)).map { |error| error["error"] }
    expect(errors).to be_empty, "#{operation.key} #{response.status} does not match the OpenAPI document: #{errors.first(3).join('; ')}"
  end
end
