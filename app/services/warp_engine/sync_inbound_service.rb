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
    # +name+ with +token+ is not taken, by the peer or the name and channel
    # lists, or +nil+ when it is.
    def refuse_upload(token:, name:, version:)
      refuse_peer(token) || refusal(@filter.reason_for(candidate(name: name), version), early: true)
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

    def refusal(reason, early: false)
      return nil if reason.nil?
      return nil if early && reason.match?(/allowed_(platforms|categories|statuses)/)

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
