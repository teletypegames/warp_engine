module WarpEngine
  # Pushes one release to one WarpEngine::SyncPeer: builds its
  # WarpEngine::Sync::Package (the files the CI uploaded, through the filter)
  # and hands it to the peer's WarpEngine::Sync::Transport; once the release
  # went through, the software's images follow when the transport carries
  # them (#push_images, which also runs alone after a gallery change). The
  # push is logged on its WarpEngine::SyncEvent and the peer's
  # +last_synced_at+ / +last_error+.
  class SyncPushService
    # The outcome of #push: the +status+ (a WarpEngine::SyncEvent status) and
    # the +message+, +nil+ when it went through.
    Result = ::Data.define(:status, :message)

    # [config] the WarpEngine::Sync::Configuration, by default WarpEngine::Sync.config
    def initialize(config: Sync.config)
      @config = config
      @filter = Sync::Filter.new(config.outbound)
    end

    # Pushes +release+ to +peer+, logging on +event+ (a queued
    # WarpEngine::SyncEvent, or +nil+ to start one) as attempt +attempt+,
    # through +filter+ (a WarpEngine::Sync::Filter; by default the configured
    # outbound one, narrowed to the peer's channels), which also chooses the
    # files. With +skip_existing+ it
    # first asks the transport what the other side has
    # (WarpEngine::Sync::Transport#existing) and sends nothing when it has the
    # version with every kind this push would bring; when the transport
    # cannot tell, the push goes ahead.
    #
    # Returns a Result: +skipped+ when outbound sync is off, the peer takes
    # no outbound pushes, the release came by sync, the filters hold it back,
    # it has no files, the other side has it already (with +skip_existing+)
    # or refuses it on purpose; +failed+ when the other side refuses it
    # otherwise; +succeeded+ when it went through. Raises
    # WarpEngine::Sync::Transport::Unreachable (after logging it) when the
    # other side does not answer, so the job tries again.
    def push(release, peer, event: nil, attempt: 1, filter: nil, skip_existing: false)
      @filter = filter if filter
      event ||= SyncEvent.log(direction: "outbound", status: "queued", sync_peer: peer, **SyncEvent.release_attributes(release))
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @files_count = 0
      @bytes = 0
      @step = nil
      @images_note = nil

      reason = skip_reason(release, peer)
      return finish(event, peer, status: "skipped", message: reason) if reason

      event&.update!(status: "running", attempt: attempt)
      run(release, peer, event, skip_existing)
    rescue Sync::Transport::Unreachable => e
      finish(event, peer, status: "failed", message: e.message)
      raise
    end

    # Sends the gallery of +software+ to +peer+ through its transport
    # (WarpEngine::Sync::Transport#deliver_images), logging on +event+ (a
    # queued WarpEngine::SyncEvent, or +nil+ to start one) as attempt
    # +attempt+. Returns a Result: +skipped+ when outbound sync is off, the
    # peer takes no outbound pushes, its transport carries no images or the
    # other side refuses on purpose; +failed+ or +succeeded+ otherwise.
    # Raises WarpEngine::Sync::Transport::Unreachable (after logging it).
    def push_images(software, peer, event: nil, attempt: 1)
      event ||= SyncEvent.log(direction: "outbound", status: "queued", sync_peer: peer, step: "images",
                              software_id: software.id, software_name: software.name, platform: software.platform)
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @files_count = 0
      @bytes = 0
      @step = "images"
      reason = images_skip_reason(peer)
      return finish(event, peer, status: "skipped", message: reason) if reason

      event&.update!(status: "running", attempt: attempt)
      images = Sync::ImageFile.of(software)
      delivery = peer.transport_instance.deliver_images(software.name, images) { |step| @step = step }
      if delivery.status == "succeeded"
        @files_count = images.size
        @bytes = images.sum { |image| File.size(image.path) }
      end
      finish(event, peer, status: delivery.status, code: delivery.code, message: delivery.message)
    rescue Sync::Transport::Unreachable => e
      finish(event, peer, status: "failed", message: e.message)
      raise
    end

    # Asks +peer+ to remove the release +version+ of the software +name+ (the
    # whole software when +version+ is +nil+) through its transport
    # (WarpEngine::Sync::Transport#deliver_removal), logging on +event+ (a
    # queued WarpEngine::SyncEvent, or +nil+ to start one) as attempt
    # +attempt+. Returns a Result: +skipped+ when outbound sync is off, the
    # peer takes no outbound pushes, its transport carries no removals, or
    # the other side has nothing of ours to remove or refuses on purpose;
    # +failed+ or +succeeded+ otherwise. Raises
    # WarpEngine::Sync::Transport::Unreachable (after logging it).
    def push_removal(peer, name:, version: nil, event: nil, attempt: 1)
      event ||= SyncEvent.log(direction: "outbound", status: "queued", sync_peer: peer, step: "remove",
                              software_name: name, version: version)
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @step = "remove"
      reason = removal_skip_reason(peer)
      return finish(event, peer, status: "skipped", message: reason) if reason

      event&.update!(status: "running", attempt: attempt)
      delivery = peer.transport_instance.deliver_removal(name, version)
      return finish(event, peer, status: "skipped", message: "the #{peer.transport} transport carries no removals") if delivery.nil?

      finish(event, peer, status: delivery.status, code: delivery.code, message: delivery.message)
    rescue Sync::Transport::Unreachable => e
      finish(event, peer, status: "failed", message: e.message)
      raise
    end

    private

    def removal_skip_reason(peer)
      return "outbound sync is not enabled" unless @config.outbound.enabled?
      return "the peer takes no outbound pushes" unless peer.outbound_enabled && peer.deleted_at.nil?
      return "unknown sync transport #{peer.transport}" if peer.transport_class.nil?

      nil
    end

    def images_skip_reason(peer)
      return "outbound sync is not enabled" unless @config.outbound.enabled?
      return "the peer takes no outbound pushes" unless peer.outbound_enabled && peer.deleted_at.nil?
      return "the #{peer.transport} transport carries no images" unless peer.transport_class&.images?

      nil
    end

    def follow_with_images(release, peer, transport)
      return unless transport.class.images?

      images = Sync::ImageFile.of(release.software)
      return if images.empty?

      delivery = transport.deliver_images(release.software.name, images)
      @images_note = "images: #{delivery.message}" unless delivery.status == "succeeded"
      peer.failed!("images: #{delivery.message}") if delivery.status == "failed"
    rescue Sync::Transport::Unreachable => e
      @images_note = "images: #{e.message}"
    end

    def skip_reason(release, peer)
      return "outbound sync is not enabled" unless @config.outbound.enabled?
      return "the peer takes no outbound pushes" unless peer.outbound_enabled && peer.deleted_at.nil?
      return "the release came by sync" if release.try(:synced?)
      return "unknown sync transport #{peer.transport}" if peer.transport_class.nil?

      @filter.for(peer).reason(release)
    end

    def run(release, peer, event, skip_existing)
      transport = peer.transport_instance
      Sync::Package.build(release, @filter) do |package|
        return finish(event, peer, status: "skipped", message: "no uploaded file of the release is left") if package.empty?

        if skip_existing && (present = present_reason(transport, package))
          return finish(event, peer, status: "skipped", message: present)
        end

        delivery = transport.deliver(package) { |step| @step = step }
        if delivery.status == "succeeded"
          @files_count = package.files.size
          @bytes = package.bytes
          follow_with_images(release, peer, transport)
        end
        finish(event, peer, status: delivery.status, code: delivery.code, message: delivery.message || @images_note)
      end
    end

    def present_reason(transport, package)
      @step = "check"
      kinds = transport.existing(package)
      return nil if kinds.nil? || kinds.empty?
      return nil if (package.kinds - kinds).any?

      "already on the peer (#{kinds.sort.join(', ')})"
    end

    def finish(event, peer, status:, code: nil, message: nil)
      event&.update!(status: status, step: @step, http_status: code, message: message,
                     files_count: @files_count, bytes: @bytes,
                     duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started) * 1000).round)
      peer.synced! if status == "succeeded"
      peer.failed!("#{@step}: #{message}") if status == "failed"
      Result.new(status: status, message: message)
    end
  end
end
