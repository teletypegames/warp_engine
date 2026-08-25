module WarpEngine

  module AccessPolicy

    class Open
      def visible_software_scope(subject: nil)
        WarpEngine::Software.kept
      end

      def access_for(software:, subject: nil)
        Access::OPEN
      end

      def authorize_download(asset: nil, subject: nil, request: nil)
        Access::Grant::OPEN
      end
    end

    class << self
      def current
        configured = WarpEngine.config.access_policy

        case configured
        when nil, :open, "open" then open_policy
        else configured
        end
      end

      def open? = current.is_a?(Open)

      def open_policy
        @open_policy ||= Open.new
      end

      def reset!
        @open_policy = nil
      end
    end
  end

  class Access

    attr_reader :gated, :entitled, :price_cents, :currency, :purchase_url, :web_url

    def initialize(gated: false, entitled: true, price_cents: nil, currency: nil,
                   purchase_url: nil, web_url: nil)
      @gated        = gated ? true : false
      @entitled     = entitled
      @price_cents  = price_cents
      @currency     = currency
      @purchase_url = purchase_url
      @web_url      = web_url
    end

    OPEN = new.freeze

    def as_json(*)
      {
        gated:       gated,
        entitled:    entitled.nil? ? nil : (entitled ? true : false),
        price:       price_cents.nil? ? nil : { amountCents: price_cents, currency: currency },
        purchaseUrl: purchase_url,
        webUrl:      web_url
      }
    end

    class Grant
      attr_reader :filename, :expires_in

      def initialize(filename: nil, expires_in: nil)
        @filename   = filename
        @expires_in = expires_in
      end

      OPEN = new.freeze
    end
  end
end
