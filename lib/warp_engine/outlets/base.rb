module WarpEngine
  module Outlets
    # Raised when an outlet definition is invalid.
    class ConfigurationError < StandardError; end

    # A format the catalog leaves the engine in. Every outlet type subclasses
    # Base and names itself with +type_name+; what it can do comes from the
    # capability modules it includes: WarpEngine::Outlets::Materialized (it
    # writes files when the catalog changes) and WarpEngine::Outlets::Served
    # (it answers requests). What it offers comes from a
    # WarpEngine::Catalog::Offer.
    #
    #   class AcmeOutlet < WarpEngine::Outlets::Base
    #     include WarpEngine::Outlets::Served
    #     def self.type_name = "acme"
    #   end
    class Base
      class << self
        # Returns the type name of the outlet class (+shelf+, +assembly64+);
        # every subclass defines it.
        def type_name
          raise NotImplementedError, "#{name} must define type_name"
        end

        # Returns +true+ when the outlet writes files (see Materialized).
        def materialized? = false

        # Returns +true+ when the outlet answers requests (see Served).
        def served? = false
      end

      # The key the outlet is configured under, a String unique among the
      # outlets, and its options as a Hash with Symbol keys.
      attr_reader :key, :options

      # [key]     the outlet key
      # [options] the definition, without +key+ and +type+
      def initialize(key, options = {})
        @key = key.to_s
        @options = options.to_h.symbolize_keys
      end

      # Returns the type name of the outlet (Base.type_name).
      def type = self.class.type_name

      # Returns the platform names whose titles the outlet carries; empty for
      # all of them.
      def platforms = []

      # Returns the WarpEngine::Catalog::Offer the outlet serves, or +nil+ for
      # an outlet that decides on its own (the catalog API).
      def offer = nil

      # Checks the definition. Raises ConfigurationError when it is invalid;
      # returns +self+ otherwise.
      def validate! = self

      # Returns the descriptor <tt>GET /api/service</tt> lists for the outlet
      # under +outlets+: +key+, +type+ and +platforms+, plus what the type adds.
      def descriptor = { key: key, type: type, platforms: platforms }

      # Returns a one-line description, e.g. <tt>assembly64 (assembly64: c64)</tt>.
      def describe = "#{key} (#{type}#{": #{platforms.join(', ')}" if platforms.any?})"

      # Returns the lines <tt>rake warp_engine:outlets:check</tt> prints for the
      # outlet: every item of its offer and every software it leaves out.
      def report
        return [] if offer.nil?

        items, skips = offer.plan
        items.map { |item| "  ok      #{item.software.name} #{item.release.version} (#{item.kind})" } +
          skips.map { |skip| "  skipped #{skip}" }
      end

      private

      def option_list(name) = Array(options[name]).map(&:to_s)

      def check_platforms!(names)
        unknown = names.reject { |name| WarpEngine::Platform.exists?(name) }
        raise ConfigurationError, "#{key}: unknown platform #{unknown.first.inspect}" if unknown.any?
      end

      def check_kinds!(names)
        raise ConfigurationError, "#{key}: needs a kind" if names.empty?

        unknown = names - WarpEngine::ReleaseAsset::KINDS
        raise ConfigurationError, "#{key}: unknown kind #{unknown.first.inspect}" if unknown.any?
      end
    end

    # The capability of an outlet that writes files: it is brought in line
    # with the catalog by WarpEngine::Outlets.refresh after every change that
    # decides its content, and by <tt>rake warp_engine:outlets:sync</tt>.
    module Materialized
      # Marks the including class as materialized.
      def self.included(base)
        base.define_singleton_method(:materialized?) { true }
      end

      # Brings the outlet's files in line with the catalog; with +dry_run+ only
      # computes what would change. Returns a result answering +changed?+.
      def sync!(dry_run: false)
        raise NotImplementedError, "#{self.class.name} must define sync!"
      end
    end

    # The capability of an outlet that answers requests. The class draws its
    # routes once (+draw_routes+), each guarded by a constraint that finds the
    # configured outlet of the type for the request (WarpEngine::Outlets.serving);
    # an outlet with +hosts+ answers only requests for those host names.
    module Served
      # Marks the including class as served.
      def self.included(base)
        base.define_singleton_method(:served?) { true }
      end

      # Returns the host names the outlet answers (its +hosts+ option, lower
      # case); empty for any host.
      def hosts = Array(options[:hosts] || options[:host]).map { |host| host.to_s.downcase }

      # Returns +true+ when the outlet answers +request+: it has no #hosts or
      # the request's host is one of them.
      def serves?(request) = hosts.empty? || hosts.include?(request.host.to_s.downcase)
    end
  end
end
