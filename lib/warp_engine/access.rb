module WarpEngine
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
