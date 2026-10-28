module WarpEngine
  # Decides who may see a title and who may download it. The policy is an
  # object with three methods (+visible_software_scope+, +access_for+,
  # +authorize_download+), set with <tt>access_policy</tt> in the configuration;
  # the default is AccessPolicy::Open.
  module AccessPolicy
    # The default policy: every kept software is listed, nothing is gated and
    # every download is allowed.
    class Open
      # Returns the scope of the titles the catalog lists for +subject+: every
      # kept WarpEngine::Software.
      def visible_software_scope(subject: nil)
        WarpEngine::Software.kept
      end

      # Returns WarpEngine::Access::OPEN for any +software+ and +subject+.
      def access_for(software:, subject: nil)
        Access::OPEN
      end

      # Allows every download: returns WarpEngine::Access::Grant::OPEN. A policy
      # returning +nil+ here refuses the download.
      def authorize_download(asset: nil, subject: nil, request: nil)
        Access::Grant::OPEN
      end
    end

    class << self
      # Returns the configured policy object; +nil+, +:open+ or <tt>"open"</tt>
      # give the shared Open instance.
      def current
        configured = WarpEngine.config.access_policy

        case configured
        when nil, :open, "open" then open_policy
        else configured
        end
      end

      # Returns +true+ when the current policy is Open.
      def open? = current.is_a?(Open)

      # Returns the memoized Open instance.
      def open_policy
        @open_policy ||= Open.new
      end

      # Drops the memoized Open instance.
      def reset!
        @open_policy = nil
      end
    end
  end

  # What a client is told about one title, as returned by the access policy's
  # +access_for+ and rendered as the +access+ block of every catalog entry.
  class Access
    # [gated]        +true+ when the title needs an entitlement
    # [entitled]     whether this caller holds it, or +nil+ when unknown
    # [price_cents]  the price in cents, or +nil+
    # [currency]     the price currency, e.g. <tt>"EUR"</tt>
    # [purchase_url] where the title can be bought
    # [web_url]      where it can be played in a browser; +nil+ keeps the engine's own path
    attr_reader :gated, :entitled, :price_cents, :currency, :purchase_url, :web_url

    # Creates the access answer from the attributes of the same names; +gated+
    # is coerced to a boolean.
    def initialize(gated: false, entitled: true, price_cents: nil, currency: nil,
                   purchase_url: nil, web_url: nil)
      @gated        = gated ? true : false
      @entitled     = entitled
      @price_cents  = price_cents
      @currency     = currency
      @purchase_url = purchase_url
      @web_url      = web_url
    end

    # The answer for an ungated, free title.
    OPEN = new.freeze

    # Returns the JSON Hash: +gated+, +entitled+, +price+
    # (<tt>{ amountCents:, currency: }</tt> or +nil+), +purchaseUrl+, +webUrl+.
    def as_json(*)
      {
        gated:       gated,
        entitled:    entitled.nil? ? nil : (entitled ? true : false),
        price:       price_cents.nil? ? nil : { amountCents: price_cents, currency: currency },
        purchaseUrl: purchase_url,
        webUrl:      web_url
      }
    end

    # The access policy's permission for one download.
    class Grant
      # [filename]   the file name to serve the download under, or +nil+ for the stored name
      # [expires_in] how long a redirect URL from the storage adapter stays valid, or +nil+
      attr_reader :filename, :expires_in

      # Creates a grant with the given +filename+ and +expires_in+.
      def initialize(filename: nil, expires_in: nil)
        @filename   = filename
        @expires_in = expires_in
      end

      # The grant with no file name or expiry.
      OPEN = new.freeze
    end
  end
end
