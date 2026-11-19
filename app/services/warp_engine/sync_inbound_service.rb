module WarpEngine
  # Decides whether a push another engine makes here with its +sync+ token is
  # taken (WarpEngine::Sync::Inbound): inbound sync must be on, the token must
  # belong to a WarpEngine::SyncPeer that accepts inbound pushes, the release
  # must pass the inbound lists, and with +protect_local+ a version this
  # engine's CI published is not overwritten. Used by the <tt>/build</tt>
  # endpoints before they upload or publish.
  class SyncInboundService
    # Why a push is refused: the HTTP +status+ to answer and the +message+.
    Refusal = ::Data.define(:status, :message)

    # The software a push names, as far as it is known before the publish.
    Candidate = Struct.new(:name, :platform, :category, :status, keyword_init: true)

    # [config] the WarpEngine::Sync::Inbound settings, by default WarpEngine::Sync.config.inbound
    def initialize(config: Sync.config.inbound)
      @config = config
      @filter = Sync::Filter.new(config)
    end

    # Returns the WarpEngine::SyncPeer that owns +token+ (a
    # WarpEngine::ApplicationToken), or +nil+.
    def peer_of(token)
      return nil unless token&.owner_type == ApplicationToken::SYNC_OWNER_TYPE

      SyncPeer.kept.find_by(id: token.owner_id)
    end

    # Returns a Refusal (403) when an upload of the +version+ of the software
    # +name+ with +token+ is not taken, by the peer or the name, channel and
    # (when the sender names it) platform lists, or +nil+ when it is.
    def refuse_upload(token:, name:, version:, platform: nil)
      refuse_peer(token) || refusal(@filter.reason_for(candidate(name: name, platform: platform.presence), version),
                                    early: true, platform_known: platform.present?)
    end

    # Returns a Refusal when the publish of +input+ (a
    # WarpEngine::PublishInputDto) with +token+ is not taken: 403 by the peer
    # or the lists (the category from the uploaded metadata, the status of the
    # software here), 409 when +protect_local+ keeps a version the CI
    # published here; +nil+ when it is taken.
    def refuse_publish(token:, input:)
      refused = refuse_peer(token)
      return refused if refused

      software = WarpEngine::Software.kept.find_by(name: input.name)
      metadata = metadata_of(input)
      refused = refusal(@filter.reason_for(candidate(name: input.name, platform: input.platform,
                                                     category: metadata[:category].presence || software&.category,
                                                     status: software&.status), input.version))
      refused || protected(software, input.version)
    end

    # Returns a Refusal when a gallery push for +software+ (a
    # WarpEngine::Software here, or +nil+) with +token+ is not taken: 403 by
    # the peer or when no release of the software passes the inbound lists,
    # 409 for a software not here, or whose images were set here by hand
    # while +protect_local+ is on; +nil+ when it is taken.
    def refuse_images(token:, software:)
      refused = refuse_peer(token)
      return refused if refused
      return Refusal.new(status: 409, message: "no such software here yet; its release comes first") if software.nil?

      reasons = software.releases.kept.map { |release| @filter.reason_for(software, release.version) }
      return Refusal.new(status: 409, message: "no release of #{software.name} here yet") if reasons.empty?
      return Refusal.new(status: 403, message: "sync inbound: #{reasons.first}") if reasons.none?(&:nil?)
      if @config.protect_local? && software.software_images.where(origin: "local").exists?
        return Refusal.new(status: 409, message: "the images of #{software.name} were set here (inbound protect_local)")
      end

      nil
    end

    private

    def refuse_peer(token)
      return Refusal.new(status: 403, message: "sync inbound is off here") unless Sync.inbound?

      peer = peer_of(token)
      return Refusal.new(status: 403, message: "this sync token belongs to no sync peer here") if peer.nil?
      return Refusal.new(status: 403, message: "inbound sync from #{peer.label} is off here") unless peer.accepts_inbound?

      nil
    end

    def candidate(name:, platform: nil, category: nil, status: nil)
      Candidate.new(name: name.to_s, platform: platform, category: category, status: status)
    end

    def refusal(reason, early: false, platform_known: false)
      return nil if reason.nil?
      return nil if early && reason.match?(/allowed_(categories|statuses)/)
      return nil if early && !platform_known && reason.match?(/allowed_platforms/)

      Refusal.new(status: 403, message: "sync inbound: #{reason}")
    end

    def protected(software, version)
      return nil unless @config.protect_local? && software

      release = software.releases.find_by(version: version)
      return nil if release.nil? || release.synced?

      Refusal.new(status: 409, message: "#{software.name} #{version} was published here by its own CI (inbound protect_local)")
    end

    def metadata_of(input)
      platform = WarpEngine::Platform.find!(input.platform)
      upload = Publish::Upload.new(name: input.name, version: input.version,
                                   root: WarpEngine::ReleaseLayout.absolute_directory(input.name, input.version))
      Publish::MetadataReader.read(platform.definition.metadata, upload)
    rescue StandardError
      {}
    end
  end
end
