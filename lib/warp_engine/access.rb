module WarpEngine
  # Who may see a title, and who may download it.
  #
  # Until now every catalog entry was public and every artifact was free: the API
  # listed all software and /api/download handed over any file it could find. That is
  # the right default for a catalog nobody sells from, and it stays the default — but a
  # host that does sell needs the engine to *say so*, because the clients reading this
  # API have no other way to learn it. A desktop client cannot know that a title is
  # paid; it can only be told.
  #
  # This module is that seam. The default policy is byte for byte the previous
  # behaviour, and a host swaps it on the configuration:
  #
  #   c.access_policy = MyStorePolicy.new   # or :open (default)
  #
  # A policy is any object answering to this contract:
  #
  #   visible_software_scope(subject:)                  -> ActiveRecord::Relation
  #   access_for(software:, subject:)                   -> WarpEngine::Access
  #   authorize_download(asset:, subject:, request:)     -> Access::Grant or nil
  #
  # `subject` is whoever the request authenticated as (see SubjectAuthentication), or
  # nil for an anonymous caller. It is deliberately untyped here: the engine has no user
  # model, and whose object this is belongs to the host.
  module AccessPolicy
    # Everything visible, everything open, no prices. The catalog as it always was.
    class Open
      def visible_software_scope(subject: nil)
        WarpEngine::Software.all
      end

      def access_for(software:, subject: nil)
        Access::OPEN
      end

      # An open catalog authorises every asset it can find. Returning a bare grant
      # rather than `true` keeps one return type across policies.
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

      # Tests and hosts that swap the configuration at runtime.
      def reset!
        @open_policy = nil
      end
    end
  end

  # What a client is told about one title's availability.
  #
  # The vocabulary is deliberately generic — `gated`, `entitled`, `price` — because
  # every client reading it serves more than one store. A word from any particular
  # host's domain ("product", "purchase order", "library") would make the client
  # that reads it specific to that host, which is exactly what this engine exists
  # to prevent.
  class Access
    # Where a hosted (browser) build is played, when the host serves it somewhere other
    # than the engine's own /file/ path. nil leaves the client with what it already
    # builds, which is the pre-existing behaviour.
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

    # An open catalog's answer, and the shape every response carries even when no
    # policy is configured: a client should never have to tell "no access block" from
    # "not gated". One of those is a question, the other is an answer.
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

    # A download the policy allowed.
    #
    # `filename` and `expires_in` let a host override what the engine would otherwise
    # decide on its own; both nil means "you choose", which is what the open policy says.
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
