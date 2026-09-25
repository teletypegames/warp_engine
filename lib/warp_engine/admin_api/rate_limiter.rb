module WarpEngine
  module AdminApi
    module RateLimiter
      module_function

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

      def retry_after(now: Time.current)
        within = AdminApi.config.rate_limit[:within].to_i
        within - (now.to_i % within)
      end
    end
  end
end
