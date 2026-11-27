require "cgi"
require "json"
require "net/http"

module WarpEngine
  # Links forks across engines (WarpEngine::Forks).
  #
  # On the fork's side, #announce tells the parent engine about a published
  # fork. On the parent's side, #receive takes an announcement and queues
  # #verify, which reads the fork back through the child engine's catalog
  # API and keeps a WarpEngine::SoftwareFork only when the fork really names one
  # of our softwares; #recheck repeats that later. #forks lists the forks of
  # a software for <tt>GET /api/softwares/:name/forks</tt>.
  class ForkService
    # The ActiveSupport::Notifications event instrumented when an announced
    # fork waits for moderation, with +software_fork+ and +software+ in the payload.
    NOTIFICATION = "warp_engine.fork_announced".freeze

    # The software names an announced fork may carry: what WarpEngine::ScaffoldService
    # accepts, plus underscores and dots older catalogs use.
    NAME_FORMAT = /\A[a-z0-9][a-z0-9._-]{0,127}\z/i

    # Raised for an announcement that cannot be taken: a malformed engine
    # URL or name.
    class InvalidAnnouncement < WarpEngine::Error; end

    # Raised when one address sent more announcements in the hour than
    # WarpEngine::Forks::Configuration#announcements_per_hour.
    class RateLimited < WarpEngine::Error; end

    # What reading a fork back found: the +title+ and the +fork_of+ Hash of
    # the child's catalog record, or the +error+.
    Lookup = ::Data.define(:title, :fork_of, :error)

    # [fetcher] callable taking a URL and returning the parsed JSON body, or
    #           raising (default: an HTTP GET with the forks timeout)
    # [poster]  callable taking a URL and a Hash body, returning the HTTP
    #           status (default: an HTTP POST of JSON)
    # [cache]   the store of the rate limit (default <tt>Rails.cache</tt>)
    def initialize(fetcher: nil, poster: nil, cache: Rails.cache)
      @fetcher = fetcher || method(:http_get)
      @poster = poster || method(:http_post)
      @cache = cache
    end

    # Queues WarpEngine::ForkAnnounceJob for +software+ when it is a fork of a
    # software on another engine and this engine announces
    # (WarpEngine::Forks.announce?). Returns whether a job was queued.
    def announce_later(software)
      return false unless announceable?(software)

      WarpEngine::ForkAnnounceJob.perform_later(software.id)
      true
    end

    # Tells the parent engine of +software+ about it:
    # <tt>POST <fork_of_engine>/api/forks</tt> with this engine's URL and the
    # software's name. Only a parent with a public address is called. Returns
    # the HTTP status, or +nil+ when nothing was sent.
    def announce(software)
      return nil unless announceable?(software)
      return nil unless WarpEngine::Forks.public_url?(software.fork_of_engine)

      @poster.call("#{software.fork_of_engine}/api/forks", { engine: WarpEngine::Forks.engine_url, name: software.name })
    end

    # Takes the announcement of the fork +name+ on the engine +engine+, sent
    # from +remote_ip+: checks the form and the rate limit and queues
    # WarpEngine::ForkVerifyJob. An announcement from a denied engine is
    # dropped quietly. Returns whether a verification was queued. Raises
    # InvalidAnnouncement or RateLimited.
    def receive(engine:, name:, remote_ip: nil)
      url = WarpEngine::Forks.normalize_url(engine)
      raise InvalidAnnouncement, "engine must be an http(s) URL" unless url.to_s.match?(%r{\Ahttps?://[^/\s]+}i)
      raise InvalidAnnouncement, "name is not a software name" unless name.to_s.match?(NAME_FORMAT)
      raise RateLimited, "too many announcements, try again later" if rate_limited?(remote_ip)
      return false if WarpEngine::Forks.denied?(url) || WarpEngine::Forks.own?(url)

      WarpEngine::ForkVerifyJob.perform_later(url, name.to_s)
      true
    end

    # Reads the fork +name+ back from the engine +engine+ and records it when
    # its catalog record names one of our kept softwares as its parent: a new
    # WarpEngine::SoftwareFork starts +pending+ (or +visible+ under +:auto+
    # moderation) and instruments NOTIFICATION while pending; a known one
    # keeps the administrator's decision (a +gone+ one comes back as new).
    # Returns the WarpEngine::SoftwareFork, or +nil+ when the fork was not confirmed.
    def verify(engine:, name:)
      return nil if WarpEngine::Forks.denied?(engine) || !WarpEngine::Forks.public_url?(engine)

      lookup = lookup(engine, name)
      parent = lookup.error ? nil : parent_of(lookup.fork_of)
      return nil unless parent

      keys = { software_id: parent.id, engine_url: engine, name: name }
      link = WarpEngine::SoftwareFork.kept.find_by(keys) || WarpEngine::SoftwareFork.revive(keys)
      reopened = link.new_record? || link.status == "gone"
      link.status = WarpEngine::Forks.config.moderation == :auto ? "visible" : "pending" if reopened
      link.assign_attributes(title: lookup.title.to_s.truncate(255).presence, checked_at: Time.current, last_error: nil)
      link.save!
      ActiveSupport::Notifications.instrument(NOTIFICATION, software_fork: link, software: parent) if reopened && link.status == "pending"
      link
    end

    # Verifies the WarpEngine::SoftwareFork +link+ again: a fork that is no longer
    # found, or no longer names its parent, becomes +gone+ (with the reason in
    # +last_error+); one found again after +gone+ waits for moderation again.
    # Returns the link.
    def recheck(link)
      lookup = lookup(link.engine_url, link.name)
      parent = lookup.error ? nil : parent_of(lookup.fork_of)
      if parent&.id == link.software_id
        reopened = link.status == "gone"
        link.status = WarpEngine::Forks.config.moderation == :auto ? "visible" : "pending" if reopened
        link.update!(title: lookup.title.to_s.truncate(255).presence || link.title, checked_at: Time.current, last_error: nil)
        ActiveSupport::Notifications.instrument(NOTIFICATION, software_fork: link, software: link.software) if reopened && link.status == "pending"
      else
        link.update!(status: "gone", checked_at: Time.current, last_error: (lookup.error || "the fork no longer names this software").truncate(512))
      end
      link
    end

    # Rechecks every kept announced fork that is not hidden and was last checked
    # longer ago than WarpEngine::Forks::Configuration#recheck_days. Returns
    # how many were rechecked.
    def recheck_due
      due = WarpEngine::SoftwareFork.kept.where.not(status: "hidden")
                                .where(checked_at: nil).or(WarpEngine::SoftwareFork.kept.where.not(status: "hidden")
                                .where(checked_at: ...WarpEngine::Forks.config.recheck_days.days.ago))
      due.find_each.count { |link| recheck(link) }
    end

    # Returns the forks of +software+ to list: its children on this engine
    # within +scope+ (the softwares the caller may see) and its visible
    # WarpEngine::SoftwareFork records, each a Hash with +engine+, +name+,
    # +title+ and +local+.
    def forks(software, scope: WarpEngine::Software.kept)
      own = WarpEngine::Forks.engine_url
      local = own ? scope.where(fork_of_engine: own, fork_of_name: software.name).order(:title).to_a : []
      remote = software.forks.where(status: "visible").order(:title, :name).to_a
      local.map { |child| { engine: own, name: child.name, title: child.title, local: true } } +
        remote.map { |link| { engine: link.engine_url, name: link.name, title: link.title.presence || link.name, local: false } }
    end

    private

    def announceable?(software)
      software.is_a?(WarpEngine::Software) && software.fork? && WarpEngine::Forks.announce? &&
        !WarpEngine::Forks.own?(software.fork_of_engine)
    end

    def parent_of(fork_of)
      return nil unless fork_of.is_a?(Hash) && WarpEngine::Forks.own?(fork_of["engine"])

      WarpEngine::Software.kept.find_by(name: fork_of["name"].to_s)
    end

    def lookup(engine, name)
      body = @fetcher.call("#{engine}/api/software?q=#{CGI.escape(name.to_s)}")
      record = softwares_in(body).find { |entry| entry.is_a?(Hash) && entry.dig("software", "name") == name.to_s }
      return Lookup.new(title: nil, fork_of: nil, error: "#{name} is not in the catalog of #{engine}") unless record

      Lookup.new(title: record.dig("software", "title"), fork_of: record.dig("software", "forkOf"), error: nil)
    rescue StandardError => e
      Lookup.new(title: nil, fork_of: nil, error: "#{engine} did not answer: #{e.message}")
    end

    def softwares_in(body)
      list = body.is_a?(Hash) ? body["softwares"] : body
      list.is_a?(Array) ? list : []
    end

    def rate_limited?(remote_ip)
      return false if remote_ip.blank?

      key = "warp_engine/fork_announcements/#{remote_ip}/#{Time.current.strftime('%Y%m%d%H')}"
      count = @cache.increment(key, 1, expires_in: 1.hour) || (@cache.write(key, 1, expires_in: 1.hour) && 1)
      count.to_i > WarpEngine::Forks.config.announcements_per_hour.to_i
    end

    def http_get(url)
      response = request(URI.parse(url)) { |uri| Net::HTTP::Get.new(uri) }
      raise WarpEngine::Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def http_post(url, body)
      request(URI.parse(url)) do |uri|
        Net::HTTP::Post.new(uri).tap do |post|
          post["Content-Type"] = "application/json"
          post.body = body.to_json
        end
      end.code.to_i
    end

    def request(uri)
      timeout = WarpEngine::Forks.config.timeout
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
        message = yield(uri)
        message["Accept"] = "application/json"
        message["User-Agent"] = "WarpEngine/#{WarpEngine::VERSION}"
        http.request(message)
      end
    end
  end
end
