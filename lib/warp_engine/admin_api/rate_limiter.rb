module WarpEngine
  module AdminApi
    # A fixed-window request counter per Principal, in <tt>Rails.cache</tt>, following
    # Configuration#rate_limit (<tt>{ to:, within: }</tt>, +within+ in seconds).
    module RateLimiter
      module_function

      # Counts one request of +principal+ in the current window and returns whether
      # it went over the limit. Always +false+ without a configured limit or principal.
      #
      # [cache] the cache store holding the counters
      # [now]   the current time
      def exceeded?(principal, cache: Rails.cache, now: Time.current)
        limit = AdminApi.config.rate_limit
        return false if limit.blank? || principal.nil?

        within = limit[:within].to_i
        return false if within <= 0

        window = now.to_i / within
        key = "warp_engine:admin_api:rate:#{principal.rate_limit_key}:#{window}"
        count = cache.increment(key, 1, expires_in: within)
        count.to_i > limit[:to].to_i
      end

      # The seconds left in the current window, for the <tt>Retry-After</tt> header.
      def retry_after(now: Time.current)
        within = AdminApi.config.rate_limit[:within].to_i
        within - (now.to_i % within)
      end
    end
  end
end
