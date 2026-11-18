module WarpEngine
  # The form of the Sync Runner admin page: reads the request +params+ into
  # the chosen peers and a WarpEngine::Sync::Criteria, and offers the
  # choices the page lists. Without params it stands for the defaults: every
  # outbound peer, the newest release, the configured filters and channels.
  class SyncRunnerForm
    # [params] the request params (ActionController::Parameters or a Hash)
    def initialize(params)
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @params = @params.stringify_keys
    end

    # Returns +true+ when the form was sent (the params carry a mode).
    def submitted? = @params.key?("mode")

    # Returns the WarpEngine::SyncPeer records that take outbound pushes, to
    # choose from, by label.
    def available_peers = @available_peers ||= WarpEngine::SyncPeer.outbound.order(:label).to_a

    # Returns the chosen peers: those ticked (or named by +peer_ids+ in a
    # link), or every outbound one before the form was sent.
    def peers
      return available_peers unless submitted? || @params.key?("peer_ids")

      ids = Array(@params["peer_ids"]).map(&:to_i)
      available_peers.select { |peer| ids.include?(peer.id) }
    end

    # Returns +true+ when +peer+ is ticked.
    def peer_checked?(peer) = peers.include?(peer)

    # Returns the WarpEngine::Sync::Criteria of the params. Raises
    # ArgumentError for an unknown channel or a sent form without one.
    def criteria
      channels = Array(@params["channels"]).compact_blank
      raise ArgumentError, "Choose at least one channel." if submitted? && channels.empty?

      @criteria ||= WarpEngine::Sync::Criteria.build(
        mode: @params["mode"], filtered: submitted? ? @params["filtered"] : true, channels: channels,
        softwares: @params["softwares"], platforms: @params["platforms"], categories: @params["categories"],
        statuses: @params["statuses"], skip_existing: submitted? ? @params["skip_existing"] : true
      )
    end

    # Returns the criteria for the page to show; the defaults when the params
    # name an unknown channel.
    def shown_criteria
      criteria
    rescue ArgumentError
      WarpEngine::Sync::Criteria.build
    end

    # Returns the platform names to narrow by.
    def platforms = WarpEngine::Platform.names

    # Returns the category keys to narrow by.
    def categories = WarpEngine::SoftwareCategory.ordered.pluck(:key)

    # Returns the status keys to narrow by.
    def statuses = WarpEngine::SoftwareStatus.keys

    # Returns the configured filter lists that are not empty, as
    # <tt>"name: values"</tt> lines, with the per-software switch first.
    def configured_filters
      config = WarpEngine::Sync.config.outbound
      lines = config.software_switch ? [ "software_switch: #{config.software_switch}" ] : []
      lines + (WarpEngine::Sync::Outbound.lists - [ :allowed_channels ]).filter_map do |name|
        values = Array(config.public_send(name))
        "#{name}: #{values.join(', ')}" if values.any?
      end
    end

    # Returns the params that bring the same form back, for a redirect.
    def to_params
      shown = shown_criteria
      { mode: shown.mode, filtered: shown.filtered ? "1" : "0", skip_existing: shown.skip_existing ? "1" : "0",
        channels: shown.channels,
        peer_ids: peers.map(&:id), softwares: shown.softwares.join(", "), platforms: shown.platforms,
        categories: shown.categories, statuses: shown.statuses }
    end
  end
end
