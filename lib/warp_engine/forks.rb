require "ipaddr"
require "resolv"
require "uri"
require "warp_engine/forks/configuration"

module WarpEngine
  # Forks link softwares across engines. A fork is a software whose metadata
  # names its parent (+fork_of_engine+, +fork_of_name+); the engine that
  # publishes it and has a public address tells the parent engine
  # (<tt>POST /api/forks</tt>), which reads the fork back through the
  # catalog API before it lists it (WarpEngine::ForkService).
  #
  #   WarpEngine.configure do
  #     forks do
  #       engine_url "https://games.example"
  #       announce true
  #       accept_announcements true
  #       moderation :pending
  #     end
  #   end
  module Forks
    # The private, loopback and link-local address ranges: an engine there is
    # not public, and its URL is never fetched.
    PRIVATE_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16
      ::1/128 fc00::/7 fe80::/10
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    # Returns the WarpEngine::Forks::Configuration of the host.
    def config = WarpEngine.config.forks

    # Returns this engine's public base URL: Configuration#engine_url, else
    # the host's site URL, normalized (see #normalize_url); +nil+ for none.
    def engine_url = normalize_url(config.engine_url.presence || WarpEngine.config.site_url)

    # Returns +url+ as an engine base URL: stripped, without a trailing slash,
    # with a lowercase scheme and host; +nil+ for a blank value. Anything
    # that does not parse as an http(s) URL comes back stripped.
    def normalize_url(url)
      text = url.to_s.strip.delete_suffix("/")
      return nil if text.empty?

      uri = URI.parse(text)
      return text unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
      uri.to_s.delete_suffix("/")
    rescue URI::InvalidURIError
      text
    end

    # Whether +url+ names this engine.
    def own?(url) = url.present? && normalize_url(url) == engine_url

    # Whether +url+ is an http(s) URL whose host resolves only to public
    # addresses (any address under Configuration#allow_private_engines). A
    # host that does not resolve is not public.
    def public_url?(url)
      uri = URI.parse(url.to_s)
      return false unless uri.is_a?(URI::HTTP) && uri.host.present?
      return true if config.allow_private_engines

      addresses = Resolv.getaddresses(uri.host)
      addresses.any? && addresses.none? { |address| private_address?(address) }
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      false
    end

    # Whether the address string +address+ is in one of PRIVATE_RANGES.
    def private_address?(address)
      ip = IPAddr.new(address)
      PRIVATE_RANGES.any? { |range| range.include?(ip) }
    end

    # Whether this engine announces its forks: Configuration#announce, not a
    # local engine, and a public #engine_url.
    def announce?
      config.announce && !WarpEngine.config.local? && engine_url.present? && public_url?(engine_url)
    end

    # Whether this engine takes announcements: Configuration#accept_announcements
    # and an #engine_url to compare them with.
    def accept_announcements? = config.accept_announcements && engine_url.present?

    # Whether the host of the engine URL +url+ is in Configuration#denied_engines.
    def denied?(url)
      host = URI.parse(url.to_s).host.to_s.downcase
      Array(config.denied_engines).map { |name| name.to_s.downcase }.include?(host)
    rescue URI::InvalidURIError
      true
    end
  end
end
