require "net/http"
require "json"
require "uri"
require "securerandom"

class CiBootstrap
  class Failure < StandardError; end

  class Browser
    def initialize
      @cookies = Hash.new { |hash, host| hash[host] = {} }
    end

    def get(url, headers: {}) = request(Net::HTTP::Get, url, headers: headers)

    def post_form(url, form, headers: {})
      request(Net::HTTP::Post, url, headers: headers) { |req| req.set_form_data(form) }
    end

    def post_json(url, body, headers: {})
      request(Net::HTTP::Post, url, headers: headers) do |req|
        req.content_type = "application/json"
        req.body = body.to_json
      end
    end

    def cookie(url, name) = @cookies[URI(url).host][name]

    private

    def request(klass, url, headers: {})
      uri = URI(url)
      req = klass.new(uri)
      jar = @cookies[uri.host]
      req["Cookie"] = jar.map { |key, value| "#{key}=#{value}" }.join("; ") if jar.any?
      headers.each { |key, value| req[key] = value }
      yield req if block_given?
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
      Array(response.get_fields("set-cookie")).each do |line|
        pair = line.split(";").first
        key, value = pair.split("=", 2)
        jar[key.strip] = value.to_s
      end
      response
    end
  end

  def initialize(env)
    @gitea = env.fetch("GITEA_URL").chomp("/")
    @woodpecker = env["WOODPECKER_URL"].to_s.chomp("/")
    @admin = env.fetch("GITEA_ADMIN")
    @password = env.fetch("GITEA_PASSWORD")
    @owner = env.fetch("GITEA_OWNER")
    @api_token = env["GITEA_API_TOKEN"]
  end

  def gitea
    ensure_org
    client = create_oauth_app
    {
      "GITEA_API_TOKEN" => create_token,
      "WOODPECKER_GITEA_CLIENT" => client["client_id"],
      "WOODPECKER_GITEA_SECRET" => client["client_secret"]
    }
  end

  def woodpecker
    token = woodpecker_token
    upsert_global_secret(token, "gitea_token", @api_token)
    { "WOODPECKER_API_TOKEN" => token }
  end

  private

  def gitea_api(klass, path, body = nil)
    uri = URI("#{@gitea}/api/v1#{path}")
    req = klass.new(uri)
    req.basic_auth(@admin, @password)
    req["Accept"] = "application/json"
    if body
      req.content_type = "application/json"
      req.body = body.to_json
    end
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
    [ response.code.to_i, response.body.to_s.empty? ? {} : JSON.parse(response.body) ]
  end

  def ensure_org
    status, = gitea_api(Net::HTTP::Get, "/orgs/#{@owner}")
    return if status == 200

    status, body = gitea_api(Net::HTTP::Post, "/orgs", { username: @owner, visibility: "public" })
    raise Failure, "gitea did not create the #{@owner} organisation: #{body['message']}" unless status == 201
  end

  def create_oauth_app
    _, apps = gitea_api(Net::HTTP::Get, "/user/applications/oauth2")
    Array(apps).select { |app| app["name"] == "Woodpecker" }.each do |app|
      gitea_api(Net::HTTP::Delete, "/user/applications/oauth2/#{app['id']}")
    end
    status, body = gitea_api(Net::HTTP::Post, "/user/applications/oauth2",
                             { name: "Woodpecker", redirect_uris: [ "#{@woodpecker}/authorize" ],
                               confidential_client: true, skip_secondary_authorization: true })
    raise Failure, "gitea did not create the OAuth app: #{body['message']}" unless status == 201

    body
  end

  def create_token
    status, body = gitea_api(Net::HTTP::Post, "/users/#{@admin}/tokens",
                             { name: "warpengine-#{SecureRandom.hex(3)}",
                               scopes: %w[write:repository write:organization write:issue read:user] })
    raise Failure, "gitea did not create the API token: #{body['message']}" unless status == 201

    body["sha1"]
  end

  def woodpecker_token
    browser = Browser.new
    login_to_gitea(browser)
    url = "#{@woodpecker}/authorize"
    response = browser.get(url)
    8.times do
      response = grant(browser, url, response) if response.is_a?(Net::HTTPOK) && url.start_with?(@gitea)
      break unless response.is_a?(Net::HTTPRedirection)

      url = URI.join(url, response["location"]).to_s
      response = browser.get(url)
    end
    raise Failure, "the Woodpecker sign-in did not finish (#{response.code})" if browser.cookie(@woodpecker, "user_sess").to_s.empty?

    config = browser.get("#{@woodpecker}/web-config.js").body.to_s
    csrf = config[/WOODPECKER_CSRF\s*=\s*"([^"]+)"/, 1]
    raise Failure, "Woodpecker sent no CSRF token" if csrf.nil?

    created = browser.post_json("#{@woodpecker}/api/user/token", {}, headers: { "X-CSRF-TOKEN" => csrf })
    raise Failure, "Woodpecker did not create a token (#{created.code})" unless created.is_a?(Net::HTTPSuccess)

    created.body.strip
  end

  def grant(browser, url, page)
    form = page.body.to_s[%r{<form[^>]*action="/login/oauth/grant".*?</form>}m]
    return page if form.nil?

    fields = form.scan(/<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"/).to_h
    browser.post_form(URI.join(url, "/login/oauth/grant").to_s, fields.merge("granted" => "true"),
                      headers: { "Origin" => @gitea })
  end

  def login_to_gitea(browser)
    page = browser.get("#{@gitea}/user/login").body.to_s
    form = { "user_name" => @admin, "password" => @password }
    csrf = page[/name="_csrf"\s+value="([^"]+)"/, 1]
    form["_csrf"] = csrf if csrf
    response = browser.post_form("#{@gitea}/user/login", form, headers: { "Origin" => @gitea })
    raise Failure, "gitea refused the #{@admin} sign-in" unless response.is_a?(Net::HTTPRedirection)
  end

  def upsert_global_secret(token, name, value)
    uri = URI("#{@woodpecker}/api/secrets")
    body = { name: name, value: value, events: %w[push tag deployment pull_request manual] }
    response = woodpecker_api(Net::HTTP::Post, uri, token, body)
    return if response.is_a?(Net::HTTPSuccess)

    response = woodpecker_api(Net::HTTP::Patch, URI("#{uri}/#{name}"), token, body)
    raise Failure, "Woodpecker did not store the #{name} secret (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
  end

  def woodpecker_api(klass, uri, token, body)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req.content_type = "application/json"
    req.body = body.to_json
    Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  end
end

step = ARGV.first
abort "usage: ruby script/ci_bootstrap.rb gitea|woodpecker" unless %w[gitea woodpecker].include?(step)
begin
  CiBootstrap.new(ENV).public_send(step).each { |key, value| puts "#{key}=#{value}" }
rescue CiBootstrap::Failure, KeyError, SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
  abort "ci_bootstrap #{step}: #{e.message}"
end
