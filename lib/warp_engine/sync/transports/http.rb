require "net/http"
require "securerandom"
require "json"
require "erb"
require "digest"
require "ipaddr"

module WarpEngine
  module Sync
    module Transports
      # The +http+ transport: another WarpEngine, reached the way its CI
      # reaches it — <tt>POST /build/upload</tt> for each file and
      # <tt>POST /build/publish</tt>, the peer's token (a +sync+ token the other
      # engine issued) in <tt>X-Update-Secret</tt>. What the other side has is
      # read from its public <tt>GET /api/softwares/:name/builds</tt>. A
      # software's images go through <tt>POST /build/images</tt> (the gallery
      # by digest) and <tt>POST /build/images/upload</tt> (the files it
      # lacks). Files are streamed, never read into memory; redirects are not
      # followed, so the token goes to no other host.
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

        # Returns +true+: the images go too.
        def self.images? = true

        # Returns the options: the +host+ (the other engine's base URL with its
        # mount) and the +token+ (secret).
        def self.options
          [ Option.new(name: "host", label: "Host", type: :string, required: true, secret: false,
                       hint: "The other engine's base URL with its mount, e.g. https://games.example.org"),
            Option.new(name: "token", label: "Token", type: :string, required: true, secret: true,
                       hint: "A sync token the other engine issued for us (its peer page: Issue inbound token)") ]
        end

        # Returns the error messages of +peer+: Transport.errors_for and a
        # host that is no http(s) URL, or plain http outside development and
        # test to a host that is not on this machine or a private network
        # (.private_host?).
        def self.errors_for(peer)
          errors = super
          host = peer.option("host").to_s
          return errors if host.blank?

          uri = URI.parse(host)
          return errors + [ "Host must be an http(s) URL" ] unless uri.is_a?(URI::HTTP) && uri.host.present?
          return errors + [ "Host must use https" ] unless uri.scheme == "https" || Rails.env.local? || private_host?(uri.host)

          errors
        rescue URI::InvalidURIError
          errors + [ "Host must be an http(s) URL" ]
        end

        # Returns +true+ for +host+ on this machine or a private network:
        # +localhost+, a name under <tt>.localhost</tt>, <tt>.local</tt> or
        # <tt>.internal</tt> (e.g. <tt>host.docker.internal</tt>), or a loopback,
        # private or link-local address.
        def self.private_host?(host)
          name = host.to_s.downcase.delete_prefix("[").delete_suffix("]")
          return true if name == "localhost" || name.end_with?(".localhost", ".local", ".internal")

          address = IPAddr.new(name)
          address.loopback? || address.private? || address.link_local?
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          false
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
                              sha256: Digest::SHA256.file(file.path).hexdigest, platform: package.software.platform)
            return refused(response) unless response.success?
          end

          yield "publish" if block_given?
          response = perform(Net::HTTP::Post.new(uri("/build/publish", name: package.name, platform: package.software.platform,
                                                                       version: package.version, commit: package.commit,
                                                                       app: package.software.try(:app))))
          response.success? ? Delivery.new(status: "succeeded", code: response.status, message: nil) : refused(response)
        end

        # Sends the gallery of the software +name+: the manifest of +images+
        # (WarpEngine::Sync::ImageFile values) first; the files the other side
        # names as missing are uploaded, then the manifest goes again and is
        # applied. A refusal of 403 or 409 (the inbound settings, images set
        # there by hand, a software it does not have) is +skipped+, another
        # error +failed+. Returns a Transport::Delivery. Raises Transport::Unreachable.
        def deliver_images(name, images)
          yield "images" if block_given?
          response = post_manifest(name, images)
          return refused(response) unless response.success?

          missing = Array(response.body["missing"]).map(&:to_s)
          if missing.any?
            images.select { |image| missing.include?(image.sha256) }.each do |image|
              yield "image:#{image.filename}" if block_given?
              uploaded = upload_image(name: name, image: image)
              return refused(uploaded) unless uploaded.success?
            end
            yield "images" if block_given?
            response = post_manifest(name, images)
            return refused(response) unless response.success?
          end
          return Delivery.new(status: "failed", code: response.status, message: "the images were not applied") unless response.body["applied"]

          Delivery.new(status: "succeeded", code: response.status, message: nil)
        end

        # Asks the other engine for the builds of the software +name+. Returns a
        # Response. Raises Transport::Unreachable.
        def builds(name)
          perform(Net::HTTP::Get.new(uri("/api/softwares/#{ERB::Util.url_encode(name.to_s)}/builds")), token: false)
        end

        # Streams the file at +path+ for the release +version+ of +name+ as
        # +filename+, with its SHA-256 +sha256+ and the +platform+ (so the other
        # side's inbound lists can refuse it before the file lands). Returns a
        # Response. Raises Transport::Unreachable.
        def upload(name:, version:, path:, filename:, sha256:, platform: nil)
          boundary = "warp-engine-sync-#{SecureRandom.hex(12)}"
          File.open(path, "rb") do |file|
            head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" \
                   "Content-Type: application/octet-stream\r\n\r\n"
            tail = "\r\n--#{boundary}--\r\n"
            request = Net::HTTP::Post.new(uri("/build/upload", name: name, version: version, sha256: sha256, platform: platform))
            request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
            request["Content-Length"] = (head.bytesize + file.size + tail.bytesize).to_s
            request.body_stream = Multipart.new([ StringIO.new(head), file, StringIO.new(tail) ])
            perform(request)
          end
        end

        private

        def post_manifest(name, images)
          request = Net::HTTP::Post.new(uri("/build/images"))
          request["Content-Type"] = "application/json"
          request.body = JSON.generate({ name: name, images: images.map(&:to_manifest) })
          perform(request)
        end

        def upload_image(name:, image:)
          boundary = "warp-engine-sync-#{SecureRandom.hex(12)}"
          File.open(image.path, "rb") do |file|
            safe = image.filename.to_s.delete("\"\r\n")
            head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{safe}\"\r\n" \
                   "Content-Type: #{image.content_type}\r\n\r\n"
            tail = "\r\n--#{boundary}--\r\n"
            request = Net::HTTP::Post.new(uri("/build/images/upload", name: name, sha256: image.sha256))
            request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
            request["Content-Length"] = (head.bytesize + file.size + tail.bytesize).to_s
            request.body_stream = Multipart.new([ StringIO.new(head), file, StringIO.new(tail) ])
            perform(request)
          end
        end

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
