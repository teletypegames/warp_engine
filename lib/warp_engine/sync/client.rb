require "net/http"
require "securerandom"
require "json"
require "erb"

module WarpEngine
  module Sync
    # Talks to another WarpEngine the way its CI does: <tt>POST /build/upload</tt>
    # and <tt>POST /build/publish</tt>, the token in <tt>X-Update-Secret</tt>.
    # Files are streamed, never read into memory; redirects are not followed,
    # so the token goes to no other host.
    class Client
      # What a request answered: the HTTP +status+, the parsed JSON +body+
      # (a Hash, empty when it was no JSON) and the engine +version+ from the
      # <tt>WarpEngine-Version</tt> header, or +nil+.
      Response = ::Data.define(:status, :body, :version) do
        # Whether the status is 2xx.
        def success? = status.between?(200, 299)

        # The +error+ of the body, else <tt>HTTP <status></tt>.
        def message = body["error"].presence || "HTTP #{status}"
      end

      # [host]    the base URL of the other engine, its mount included
      # [secret]  the token with the +sync+ scope it issued
      # [timeout] seconds a request may take
      def initialize(host:, secret:, timeout: Sync.config.timeout)
        @base = URI.parse(host.to_s.chomp("/"))
        @secret = secret.to_s
        @timeout = timeout.to_i
      end

      # Uploads the file at +path+ for the release +version+ of +name+, under
      # +filename+ (default: its own name), with its SHA-256 +sha256+ for the
      # other side to check. Returns a Response.
      # Raises WarpEngine::Sync::ConnectionError when the host does not answer.
      def upload(name:, version:, path:, sha256:, filename: nil)
        boundary = "warp-engine-sync-#{SecureRandom.hex(12)}"
        File.open(path, "rb") do |file|
          head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename || File.basename(path)}\"\r\n" \
                 "Content-Type: application/octet-stream\r\n\r\n"
          tail = "\r\n--#{boundary}--\r\n"
          request = Net::HTTP::Post.new(uri("/build/upload", name: name, version: version, sha256: sha256))
          request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
          request["Content-Length"] = (head.bytesize + file.size + tail.bytesize).to_s
          request.body_stream = Multipart.new([ StringIO.new(head), file, StringIO.new(tail) ])
          perform(request)
        end
      end

      # Publishes the uploaded release +version+ of +name+ on +platform+, with
      # the +commit+ it was built of. Returns a Response. Raises
      # WarpEngine::Sync::ConnectionError when the host does not answer.
      def publish(name:, platform:, version:, commit: nil)
        perform(Net::HTTP::Post.new(uri("/build/publish", name: name, platform: platform, version: version, commit: commit)))
      end

      # Asks which releases of the software +name+ the other engine has, and
      # with which asset kinds (<tt>GET /api/softwares/:name/builds</tt>, the
      # same read its CI checklist uses). Returns a Response: 200 with
      # +releases+ (version to <tt>{ "actual" => kinds }</tt>), 404 when it
      # has no such software. The token is not sent: the read is public. Raises WarpEngine::Sync::ConnectionError when
      # the host does not answer.
      def builds(name)
        perform(Net::HTTP::Get.new(uri("/api/softwares/#{ERB::Util.url_encode(name.to_s)}/builds")), secret: false)
      end

      # Checks the token without changing anything: an upload without a file
      # answers 400 for a token the other side accepts and 401 for one it
      # does not. Returns a Response. Raises WarpEngine::Sync::ConnectionError
      # when the host does not answer.
      def check
        perform(Net::HTTP::Post.new(uri("/build/upload")))
      end

      private

      def uri(path, **query)
        target = @base.dup
        target.path = "#{@base.path}#{path}"
        params = query.compact_blank
        target.query = URI.encode_www_form(params) if params.any?
        target
      end

      def perform(request, secret: true)
        request["X-Update-Secret"] = @secret if secret
        request["Accept"] = "application/json"
        response = Net::HTTP.start(@base.host, @base.port, use_ssl: @base.scheme == "https",
                                   open_timeout: 10, read_timeout: @timeout, write_timeout: @timeout) do |http|
          http.request(request)
        end
        Response.new(status: response.code.to_i, body: parse(response.body), version: response["WarpEngine-Version"])
      rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
        raise ConnectionError, "#{@base.host}: #{e.class.name}: #{e.message}"
      end

      def parse(body)
        parsed = JSON.parse(body.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      # Reads several IO objects one after the other, as the body stream of a
      # request.
      class Multipart
        # [parts] the IO objects, read in order
        def initialize(parts)
          @parts = parts
        end

        # Reads up to +length+ bytes (all that is left without one) into
        # +buffer+ when given, as IO#read does; returns +nil+ at the end.
        def read(length = nil, buffer = nil)
          data = +""
          while (part = @parts.first)
            chunk = part.read(length && (length - data.bytesize))
            data << chunk.to_s
            @parts.shift if chunk.nil? || chunk.empty? || part.eof?
            break if length && data.bytesize >= length
          end
          return (length ? nil : "") if data.empty? && length

          buffer ? buffer.replace(data) : data
        end
      end
    end
  end
end
