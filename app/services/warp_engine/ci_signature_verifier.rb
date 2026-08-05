require "openssl"
require "base64"
require "net/http"

module WarpEngine
  # Verifies the httpsig signature of Woodpecker configuration-extension
  # requests (draft-cavage http-signatures, ed25519). The server sends the
  # signed header list in the Signature header — typically "(request-target) date".
  class CiSignatureVerifier
    SIGNATURE_PARAM = /(\w+)="([^"]*)"/

    @key_cache = {}
    @key_mutex = Mutex.new

    class << self
      # The downloaded key is cached process-wide (per URL).
      def fetch_public_key(url)
        @key_mutex.synchronize do
          @key_cache[url] ||= Net::HTTP.get(URI.parse(url))
        end
      end

      def reset_key_cache!
        @key_mutex.synchronize { @key_cache = {} }
      end
    end

    def initialize(request)
      @request = request
    end

    def valid?
      pem = public_key_pem
      if pem.blank?
        Rails.logger.error("[CiSignatureVerifier] no ci_extension_public_key(_url) configured — rejecting request")
        return false
      end

      params = signature_params
      return false if params.nil? || params["signature"].blank?

      signing_string = build_signing_string(params.fetch("headers", "date"))
      return false if signing_string.nil?

      key = OpenSSL::PKey.read(pem)
      key.verify(nil, Base64.decode64(params["signature"]), signing_string)
    rescue OpenSSL::PKey::PKeyError, ArgumentError => e
      Rails.logger.error("[CiSignatureVerifier] #{e.class}: #{e.message}")
      false
    end

    private

    def public_key_pem
      config = WarpEngine.config
      return config.ci_extension_public_key if config.ci_extension_public_key.present?
      return nil if config.ci_extension_public_key_url.blank?

      self.class.fetch_public_key(config.ci_extension_public_key_url)
    rescue StandardError => e
      Rails.logger.error("[CiSignatureVerifier] public key fetch failed: #{e.class}: #{e.message}")
      nil
    end

    # Parameters of the Signature header (or the "Authorization: Signature ..." form).
    def signature_params
      header = @request.headers["Signature"].presence
      if header.nil?
        auth = @request.headers["Authorization"].to_s
        header = auth.delete_prefix("Signature ") if auth.start_with?("Signature ")
      end
      return nil if header.blank?

      header.scan(SIGNATURE_PARAM).to_h
    end

    def build_signing_string(headers_list)
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
