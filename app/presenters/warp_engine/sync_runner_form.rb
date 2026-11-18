module WarpEngine
  # The form of the Sync Runner admin page: reads the request +params+ into
  # the chosen servers and a WarpEngine::Sync::Criteria, and offers the
  # choices the page lists. Without params it stands for the defaults: every
  # active server, the newest release, the configured filters and channels.
  class SyncRunnerForm
    # [params] the request params (ActionController::Parameters or a Hash)
    def initialize(params)
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @params = @params.stringify_keys
    end

    # Returns +true+ when the form was sent (the params carry a mode).
    def submitted? = @params.key?("mode")

    # Returns the active WarpEngine::SyncServer records to choose from, by label.
    def available_servers = @available_servers ||= WarpEngine::SyncServer.active.order(:label).to_a

    # Returns the chosen servers: those ticked, or every active one before the
    # form was sent.
    def servers
      return available_servers unless submitted?

      ids = Array(@params["server_ids"]).map(&:to_i)
      available_servers.select { |server| ids.include?(server.id) }
    end

    # Returns +true+ when +server+ is ticked.
    def server_checked?(server) = servers.include?(server)

    # Returns the WarpEngine::Sync::Criteria of the params. Raises
    # ArgumentError for an unknown channel or a sent form without one.
    def criteria
      channels = Array(@params["channels"]).compact_blank
      raise ArgumentError, "Choose at least one channel." if submitted? && channels.empty?

      @criteria ||= WarpEngine::Sync::Criteria.build(
        mode: @params["mode"], filtered: submitted? ? @params["filtered"] : true, channels: channels,
        softwares: @params["softwares"], platforms: @params["platforms"], categories: @params["categories"],
        statuses: @params["statuses"]
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
      config = WarpEngine::Sync.config
      lines = config.software_switch ? [ "software_switch: #{config.software_switch}" ] : []
      lines + (WarpEngine::Sync::Configuration::LISTS - [ :allowed_channels ]).filter_map do |name|
        values = Array(config.public_send(name))
        "#{name}: #{values.join(', ')}" if values.any?
      end
    end

    # Returns the params that bring the same form back, for a redirect.
    def to_params
      shown = shown_criteria
      { mode: shown.mode, filtered: shown.filtered ? "1" : "0", channels: shown.channels,
        server_ids: servers.map(&:id), softwares: shown.softwares.join(", "), platforms: shown.platforms,
        categories: shown.categories, statuses: shown.statuses }
    end
  end
end
