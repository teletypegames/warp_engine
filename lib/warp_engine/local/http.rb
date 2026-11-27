require "net/http"
require "json"
require "uri"

module WarpEngine
  module Local
    # The HTTP the providers' bootstrap speaks: JSON API calls
    # (#json) and a small browser (#get, #post_form, #post_json) that keeps
    # cookies per host, for the sign-ins that have no API. Addresses under
    # one of the +rewrites+ prefixes are fetched from the address they map to,
    # so a page that names the git server's public address
    # (<tt>http://localhost:7471</tt>) is followed on the network the engine
    # shares with it.
    class Http
      # A call did not go through: the server is down, or it refused.
      class Error < Local::Error; end

      # [rewrites] a Hash of public URL prefix to the URL prefix to fetch instead
      def initialize(rewrites: {})
        @rewrites = rewrites
        @cookies = Hash.new { |hash, host| hash[host] = {} }
      end

      # Sends a JSON request: +method+ (+:get+, +:post+, +:patch+, +:put+,
      # +:delete+) to +url+ with +body+ (or +nil+), HTTP basic auth +basic+
      # (<tt>[user, password]</tt>) or +token+ (<tt>Authorization: token</tt>,
      # or +bearer+). Returns <tt>[status, parsed body]</tt> (an empty Hash for
      # no JSON). Raises Error when the server does not answer.
      def json(method, url, body = nil, basic: nil, token: nil, bearer: nil)
        response = perform(url, method) do |request|
          request.basic_auth(*basic) if basic
          request["Authorization"] = "token #{token}" if token
          request["Authorization"] = "Bearer #{bearer}" if bearer
          request["Accept"] = "application/json"
          if body
            request.content_type = "application/json"
            request.body = JSON.generate(body)
          end
        end
        [ response.code.to_i, parse(response.body) ]
      end

      # Fetches +url+ with the cookies of its host. Returns the Net::HTTPResponse.
      def get(url, headers: {}) = browse(url, :get, headers)

      # Posts +form+ to +url+. Returns the Net::HTTPResponse.
      def post_form(url, form, headers: {})
        browse(url, :post, headers) { |request| request.set_form_data(form) }
      end

      # Posts +body+ as JSON to +url+. Returns the Net::HTTPResponse.
      def post_json(url, body, headers: {})
        browse(url, :post, headers) do |request|
          request.content_type = "application/json"
          request.body = JSON.generate(body)
        end
      end

      # Returns the cookie +name+ the host of +url+ set.
      def cookie(url, name) = @cookies[URI(rewrite(url)).host][name]

      # Returns +url+ with a rewritten prefix, or as it is.
      def rewrite(url)
        @rewrites.each { |from, to| return url.sub(from, to) if url.start_with?(from) }
        url
      end

      # Returns +true+ when +url+ answers 2xx within +timeout+ seconds.
      def up?(url, timeout: 3)
        uri = URI(rewrite(url))
        Net::HTTP.start(uri.host, uri.port, open_timeout: timeout, read_timeout: timeout) { |http| http.get(uri.request_uri) }
                 .is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      private

      def browse(url, method, headers)
        uri = URI(rewrite(url))
        jar = @cookies[uri.host]
        response = perform(url, method) do |request|
          request["Cookie"] = jar.map { |key, value| "#{key}=#{value}" }.join("; ") if jar.any?
          headers.each { |key, value| request[key] = value }
          yield request if block_given?
        end
        Array(response.get_fields("set-cookie")).each do |line|
          key, value = line.split(";").first.split("=", 2)
          jar[key.strip] = value.to_s
        end
        response
      end

      def perform(url, method)
        uri = URI(rewrite(url))
        request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
        yield request
        Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
      rescue SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "#{uri&.host}: #{e.message}"
      end

      def parse(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
