require "openssl"
require "base64"
require "net/http"
require "digest"

module WarpEngine
  module CI
    module Woodpecker
      # Verifies the HTTP signature Woodpecker puts on its configuration extension
      # requests, in either RFC 9421 (<tt>Signature-Input</tt>) or the older Cavage
      # draft form, against the configured public key (ed25519 PEM). Fetched public
      # keys are cached per URL for the life of the process.
      class SignatureVerifier
        # The pattern of one <tt>key="value"</tt> parameter of a Cavage +Signature+ header.
        CAVAGE_PARAM = /(\w+)="([^"]*)"/

        @key_cache = {}
        @key_mutex = Mutex.new

        class << self
          # Returns the PEM body at +url+, fetched once per URL and then cached (thread-safe).
          def fetch_public_key(url)
            @key_mutex.synchronize do
              @key_cache[url] ||= Net::HTTP.get(URI.parse(url))
            end
          end

          # Empties the public key cache.
          def reset_key_cache!
            @key_mutex.synchronize { @key_cache = {} }
          end
        end

        # [request]        the incoming ActionDispatch::Request
        # [public_key]     the PEM public key, preferred when given
        # [public_key_url] the URL to fetch the PEM public key from otherwise
        def initialize(request, public_key: nil, public_key_url: nil)
          @request        = request
          @public_key     = public_key
          @public_key_url = public_key_url
        end

        # Returns +true+ when the request's signature verifies against the public key.
        # Returns +false+, logging the reason, when no key is configured or can be
        # fetched, the key cannot be read, a signed component is missing, or the
        # content digest or signature does not match.
        def valid?
          pem = public_key_pem
          if pem.blank?
            Rails.logger.error("[CI::Woodpecker] no public key configured — rejecting request")
            return false
          end

          key = OpenSSL::PKey.read(pem)
          if @request.headers["Signature-Input"].present?
            rfc9421_valid?(key)
          else
            cavage_valid?(key)
          end
        rescue OpenSSL::PKey::PKeyError, ArgumentError => e
          Rails.logger.error("[CI::Woodpecker] #{e.class}: #{e.message}")
          false
        end

        private

        def public_key_pem
          return @public_key if @public_key.present?
          return nil if @public_key_url.blank?

          self.class.fetch_public_key(@public_key_url)
        rescue StandardError => e
          Rails.logger.error("[CI::Woodpecker] public key fetch failed: #{e.class}: #{e.message}")
          nil
        end

        def rfc9421_valid?(key)
          input = @request.headers["Signature-Input"].to_s
          match = input.match(/\A\s*([\w.-]+)=(\(.*)\z/m)
          return false if match.nil?

          label, inner = match[1], match[2]
          components = inner[/\((.*?)\)/m, 1].to_s.scan(/"([^"]*)"/).flatten
          return false if components.empty?

          signature = @request.headers["Signature"].to_s[/#{Regexp.escape(label)}=:([A-Za-z0-9+\/=]+):/, 1]
          return false if signature.blank?
          return false unless content_digest_valid?(components)

          lines = components.map do |component|
            value = component_value(component)
            return false if value.nil?
            %("#{component}": #{value})
          end
          lines << %("@signature-params": #{inner})

          key.verify(nil, Base64.decode64(signature), lines.join("\n"))
        end

        def component_value(name)
          case name
          when "@request-target" then @request.fullpath
          when "@method"         then @request.request_method
          when "@target-uri"     then @request.original_url
          when "@authority"      then @request.host_with_port
          when "@path"           then @request.path
          when "@query"          then "?#{@request.query_string}"
          when /\A@/             then nil
          else @request.headers[name]
          end
        end

        def content_digest_valid?(components)
          return true unless components.include?("content-digest")

          digest = @request.headers["Content-Digest"].to_s[/sha-256=:([A-Za-z0-9+\/=]+):/, 1]
          return false if digest.blank?

          expected = Digest::SHA256.base64digest(@request.raw_post)
          ActiveSupport::SecurityUtils.secure_compare(digest, expected)
        end

        def cavage_valid?(key)
          params = cavage_params
          return false if params.nil? || params["signature"].blank?

          signing_string = cavage_signing_string(params.fetch("headers", "date"))
          return false if signing_string.nil?

          key.verify(nil, Base64.decode64(params["signature"]), signing_string)
        end

        def cavage_params
          header = @request.headers["Signature"].presence
          if header.nil?
            auth = @request.headers["Authorization"].to_s
            header = auth.delete_prefix("Signature ") if auth.start_with?("Signature ")
          end
          return nil if header.blank?

          header.scan(CAVAGE_PARAM).to_h
        end

        def cavage_signing_string(headers_list)
          lines = headers_list.split(" ").map do |name|
            if name == "(request-target)"
              "(request-target): #{@request.request_method.downcase} #{@request.fullpath}"
            else
              value = @request.headers[name]
              return nil if value.nil?
              "#{name.downcase}: #{value}"
            end
          end
          lines.join("\n")
        end
      end
    end
  end
end
