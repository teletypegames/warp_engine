require "net/http"
require "json"
require "uri"

module WarpEngine
  module Forge
    # A Gitea (or Forgejo) forge: creates repositories in one organisation
    # through the REST API with a token that may create repositories there.
    class Gitea
      # [url]          the server URL (a trailing slash is dropped)
      # [token]        the API token, sent as <tt>Authorization: token</tt>
      # [owner]        the organisation new repositories go to
      # [private]      whether new repositories are private (default +false+)
      # [branch]       the default branch of new repositories (default +master+)
      # [open_timeout] seconds to wait for the connection (default 10)
      # [read_timeout] seconds to wait for an answer (default 30)
      def initialize(url:, token:, owner:, private: false, branch: "master", open_timeout: 10, read_timeout: 30)
        @base_url = url.to_s.chomp("/")
        @token = token
        @owner = owner.to_s
        @private = private
        @branch = branch.to_s
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # The organisation new repositories go to.
      attr_reader :owner

      # Returns <tt>"Gitea"</tt>.
      def name = "Gitea"

      # Returns +true+ when the URL, the token and the owner are set.
      def configured? = @base_url.present? && @token.present? && @owner.present?

      # Creates the empty repository +name+ in the organisation, with
      # +description+. Returns the Repo. Raises Forge::Error when the forge
      # refuses (e.g. the name is taken) or cannot be reached.
      def create_repo(name:, description: nil)
        body = { name: name, description: description.to_s, private: @private, default_branch: @branch, auto_init: false }
        to_repo(request(Net::HTTP::Post, "/api/v1/orgs/#{@owner}/repos", body))
      end

      # Returns the Repo +name+ of the organisation, or +nil+ when there is
      # none. Raises Forge::Error when the forge cannot be reached.
      def find_repo(name)
        to_repo(request(Net::HTTP::Get, "/api/v1/repos/#{@owner}/#{name}", nil))
      rescue Error => e
        raise unless e.message.include?("answered 404")

        nil
      end

      # Returns the number of the open pull request of +owner+/+name+ whose
      # source branch is +branch+ (compared with its slashes as dashes, the
      # way the CI names a development build), or +nil+. Raises Forge::Error.
      def open_pull_request(owner:, name:, branch:)
        wanted = branch.to_s.tr("/", "-")
        pulls = request(Net::HTTP::Get, "/api/v1/repos/#{owner}/#{name}/pulls?state=open&limit=50", nil)
        Array(pulls).find { |pull| pull.dig("head", "ref").to_s.tr("/", "-") == wanted }&.dig("number")
      end

      # Writes +body+ as the comment of pull request (or issue) +number+ of
      # +owner+/+name+ that carries +marker+: the existing one is changed, a new
      # one is added when there is none. Returns the comment id. Raises
      # Forge::Error (the token needs the +write:issue+ scope).
      def upsert_comment(owner:, name:, number:, marker:, body:)
        text = "#{body}\n\n#{marker}"
        comments = request(Net::HTTP::Get, "/api/v1/repos/#{owner}/#{name}/issues/#{number}/comments", nil)
        existing = Array(comments).find { |comment| comment["body"].to_s.include?(marker) }
        if existing
          request(Net::HTTP::Patch, "/api/v1/repos/#{owner}/#{name}/issues/comments/#{existing['id']}", { body: text })["id"]
        else
          request(Net::HTTP::Post, "/api/v1/repos/#{owner}/#{name}/issues/#{number}/comments", { body: text })["id"]
        end
      end

      private

      def to_repo(remote)
        Repo.new(id: remote["id"], owner: remote.dig("owner", "login") || @owner, name: remote["name"],
                 html_url: remote["html_url"], clone_url: remote["clone_url"], ssh_url: remote["ssh_url"])
      end

      def request(klass, path, body)
        uri = URI("#{@base_url}#{path}")
        request = klass.new(uri)
        request["Authorization"] = "token #{@token}"
        request["Accept"] = "application/json"
        unless body.nil?
          request.content_type = "application/json"
          request.body = body.to_json
        end
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                       open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(request)
        end
        parsed = response.body.present? ? JSON.parse(response.body) : {}
        return parsed if response.is_a?(Net::HTTPSuccess)

        raise Error, "#{name} answered #{response.code}: #{parsed['message'] || response.message}"
      rescue JSON::ParserError
        raise Error, "#{name} answered #{response&.code} with no JSON"
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "#{name} cannot be reached: #{e.message}"
      end
    end
  end
end
