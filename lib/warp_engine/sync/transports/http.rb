require "net/http"
require "securerandom"
require "json"
require "erb"
require "digest"

module WarpEngine
  module Sync
    module Transports
      # The +http+ transport: another WarpEngine, reached the way its CI
      # reaches it — <tt>POST /build/upload</tt> for each file and
      # <tt>POST /build/publish</tt>, the peer's token (a +sync+ token the other
      # engine issued) in <tt>X-Update-Secret</tt>. What the other side has is
      # read from its public <tt>GET /api/softwares/:name/builds</tt>. Files are
      # streamed, never read into memory; redirects are not followed, so the
      # token goes to no other host.
      class Http < Transport
        # What a request answered: the HTTP +status+, the parsed JSON +body+
        # (a Hash, empty when it was no JSON) and the engine +version+ from the
        # <tt>WarpEngine-Version</tt> header, or +nil+.
        Response = ::Data.define(:status, :body, :version) do
          # Whether the status is 2xx.
          def success? = status.between?(200, 299)

          # The +error+ of the body, else <tt>HTTP <status></tt>.
          def message = body["error"].presence || "HTTP #{status}"
        end

        # Returns <tt>"http"</tt>.
        def self.key = "http"

        # Returns the human name.
        def self.label = "WarpEngine (HTTP)"

        # Returns +true+: the other side is a WarpEngine that publishes.
        def self.publishes? = true

        # Returns the options: the +host+ (the other engine's base URL with its
        # mount) and the +token+ (secret).
        def self.options
          [ Option.new(name: "host", label: "Host", type: :string, required: true, secret: false,
                       hint: "The other engine's base URL with its mount, e.g. https://games.example.org"),
            Option.new(name: "token", label: "Token", type: :string, required: true, secret: true,
                       hint: "A sync token the other engine issued for us (its peer page: Issue inbound token)") ]
        end

        # Returns the error messages of +peer+: Transport.errors_for and a
        # host that is no http(s) URL, or plain http outside development and test.
        def self.errors_for(peer)
          errors = super
          host = peer.option("host").to_s
          return errors if host.blank?

          uri = URI.parse(host)
          return errors + [ "Host must be an http(s) URL" ] unless uri.is_a?(URI::HTTP) && uri.host.present?
          return errors + [ "Host must use https" ] unless uri.scheme == "https" || Rails.env.local?

          errors
        rescue URI::InvalidURIError
          errors + [ "Host must be an http(s) URL" ]
        end

        # Posts an upload without a file: the other side answers 400 to a
        # token it accepts and 401 to one it does not. Returns a
        # Transport::CheckResult.
        def check
          return CheckResult.new(ok: false, status: nil, version: nil, message: "the token does not decrypt; enter it again") if secret.nil?

          response = perform(Net::HTTP::Post.new(uri("/build/upload")))
          case response.status
          when 400 then CheckResult.new(ok: true, status: 400, version: response.version, message: "the token is accepted")
          when 401, 403 then CheckResult.new(ok: false, status: response.status, version: response.version,
                                             message: "the token is refused: #{base_url} needs to issue it with the sync scope")
          else CheckResult.new(ok: false, status: response.status, version: response.version, message: response.message)
          end
        rescue Unreachable => e
          CheckResult.new(ok: false, status: nil, version: nil, message: e.message)
        end

        # Returns the kinds the other engine has of +package+'s version, an
        # empty Array when it has no such version or software, or +nil+ when
        # the question goes unanswered.
        def existing(package)
          response = builds(package.name)
          return [] if response.status == 404
          return nil unless response.success?

          release = response.body.fetch("releases", {})[package.version]
          release ? Array(release["actual"]).map(&:to_s) : []
        rescue Unreachable
          nil
        end

        # Uploads every file of +package+ under its name, then publishes it.
        # A refusal of 403 (the other side's inbound settings) or 409 (it has
        # a newer version, or protects its own) is +skipped+, another error
        # +failed+. Returns a Transport::Delivery. Raises Transport::Unreachable.
        def deliver(package)
          package.files.each do |file|
            yield "upload:#{file.name}" if block_given?
            response = upload(name: package.name, version: package.version, path: file.path, filename: file.name,
                              sha256: Digest::SHA256.file(file.path).hexdigest)
            return refused(response) unless response.success?
          end

          yield "publish" if block_given?
          response = perform(Net::HTTP::Post.new(uri("/build/publish", name: package.name, platform: package.software.platform,
                                                                       version: package.version, commit: package.commit)))
          response.success? ? Delivery.new(status: "succeeded", code: response.status, message: nil) : refused(response)
        end

        # Asks the other engine for the builds of the software +name+. Returns a
        # Response. Raises Transport::Unreachable.
        def builds(name)
          perform(Net::HTTP::Get.new(uri("/api/softwares/#{ERB::Util.url_encode(name.to_s)}/builds")), token: false)
        end

        # Streams the file at +path+ for the release +version+ of +name+ as
        # +filename+, with its SHA-256 +sha256+. Returns a Response. Raises
        # Transport::Unreachable.
        def upload(name:, version:, path:, filename:, sha256:)
          boundary = "warp-engine-sync-#{SecureRandom.hex(12)}"
          File.open(path, "rb") do |file|
            head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" \
                   "Content-Type: application/octet-stream\r\n\r\n"
            tail = "\r\n--#{boundary}--\r\n"
            request = Net::HTTP::Post.new(uri("/build/upload", name: name, version: version, sha256: sha256))
            request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
            request["Content-Length"] = (head.bytesize + file.size + tail.bytesize).to_s
            request.body_stream = Multipart.new([ StringIO.new(head), file, StringIO.new(tail) ])
            perform(request)
          end
        end

        private

        def base_url = option("host").to_s.strip.chomp("/")

        def timeout = WarpEngine::Sync.config.outbound.timeout.to_i

        def refused(response)
          status = [ 403, 409 ].include?(response.status) ? "skipped" : "failed"
          Delivery.new(status: status, code: response.status, message: response.message)
        end

        def uri(path, **query)
          base = URI.parse(base_url)
          base.path = "#{base.path}#{path}"
          params = query.compact_blank
          base.query = URI.encode_www_form(params) if params.any?
          base
        end

        def perform(request, token: true)
          request["X-Update-Secret"] = secret.to_s if token
          request["Accept"] = "application/json"
          target = request.uri || URI.parse(base_url)
          response = Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https",
                                     open_timeout: 10, read_timeout: timeout, write_timeout: timeout) do |http|
            http.request(request)
          end
          Response.new(status: response.code.to_i, body: parse(response.body), version: response["WarpEngine-Version"])
        rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
          raise Unreachable, "#{target&.host}: #{e.class.name}: #{e.message}"
        end

        def parse(body)
          parsed = JSON.parse(body.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        # Reads several IO objects one after the other, as the body stream of
        # a request.
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
end
