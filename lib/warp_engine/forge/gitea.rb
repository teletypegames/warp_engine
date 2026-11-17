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
        request.content_type = "application/json"
        request.body = body.to_json
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
