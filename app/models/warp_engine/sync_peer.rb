module WarpEngine
  # Another engine (or place) this one syncs with (table +sync_peers+), in
  # either direction or both:
  #
  # [outbound] when +outbound_enabled+, the releases are pushed to it through
  #            its +transport+ (a WarpEngine::Sync::Transport key, +http+ by
  #            default) with the +transport_options+ (e.g. the +host+) and the
  #            +secret+ (the transport's secret option, e.g. the token the
  #            other engine issued), stored encrypted
  #            (WarpEngine::Sync::SecretBox) with its first characters in
  #            +secret_prefix+; an empty secret on an update keeps the stored one
  # [inbound]  when +inbound_enabled+, it may push here with the +sync+ token
  #            this engine issued to it (#issue_inbound_token!), whose owner it is
  #
  # +allowed_channels+ narrows the outbound +allowed_channels+ for this peer
  # (empty: the global list). +created_by+ is who paired it through the
  # +sync_pairings+ resource of the Admin API (+nil+ for a peer an
  # administrator made); the +paired_by+ scope finds a caller's own.
  #
  # +last_synced_at+ and +last_error+ tell how its last outbound push went.
  # Soft-deletable; the +outbound+ scope holds the kept peers that take
  # outbound pushes.
  class SyncPeer < ApplicationRecord
    self.table_name = "sync_peers"

    # The prefix of the per-option readers (see #method_missing).
    OPTION_READER = "transport_option_".freeze

    include SoftDeletable

    has_many :sync_events, foreign_key: :sync_peer_id, inverse_of: :sync_peer
    has_many :releases, foreign_key: :sync_peer_id, inverse_of: :sync_peer
    belongs_to :inbound_token, class_name: "WarpEngine::ApplicationToken", optional: true
    belongs_to :created_by, polymorphic: true, optional: true

    scope :outbound, -> { kept.where(outbound_enabled: true) }
    scope :paired_by, ->(owner) { kept.where(created_by_type: owner.class.name, created_by_id: owner.id) }

    validates :label, presence: true, length: { maximum: 128 }
    validate :transport_is_known
    validate :transport_options_are_complete
    validate :allowed_channels_are_known

    # Returns the decrypted secret, or +nil+ when none is stored or it does
    # not decrypt with the current key.
    def secret
      Sync::SecretBox.decrypt(self[:secret])
    end

    # Stores +value+ encrypted and keeps its prefix; a blank +value+ leaves
    # the stored secret as it is.
    def secret=(value)
      return if value.blank?

      self[:secret] = Sync::SecretBox.encrypt(value.to_s.strip)
      self.secret_prefix = value.to_s.strip.first(8)
    end

    # Returns the transport option +name+ (a String key of +transport_options+).
    def option(name) = transport_options.to_h[name.to_s]

    # Answers <tt>transport_option_<name></tt> with the option +name+, so a
    # form can show each transport option as a field of its own.
    def method_missing(method, *args)
      return option(method.to_s.delete_prefix(OPTION_READER)) if method.to_s.start_with?(OPTION_READER) && args.empty?

      super
    end

    # Returns +true+ for the <tt>transport_option_<name></tt> readers (see #method_missing).
    def respond_to_missing?(method, include_private = false)
      method.to_s.start_with?(OPTION_READER) || super
    end

    # Returns the channels this peer narrows the outbound pushes to, as
    # strings; empty when it takes what the global list allows.
    def channels = Array(allowed_channels).map(&:to_s).compact_blank.uniq

    # Sets the channels from an Array or a comma or space separated string;
    # blank clears them.
    def allowed_channels=(value)
      list = value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)
      super(list.map { |channel| channel.to_s.strip }.compact_blank.uniq.presence)
    end

    # Returns the transport class (WarpEngine::Sync::Transports.find), or +nil+.
    def transport_class = Sync::Transports.find(transport)

    # Returns a WarpEngine::Sync::Transport working for this peer. Raises
    # WarpEngine::Error for an unknown transport.
    def transport_instance
      klass = transport_class
      raise WarpEngine::Error, "unknown sync transport #{transport.inspect}" if klass.nil?

      klass.new(self)
    end

    # Returns where the outbound pushes go, for a person: the +host+ or
    # +path+ option, else the transport's name.
    def target = option("host").presence || option("path").presence || transport.to_s

    # Returns +true+ while inbound pushes from this peer are accepted: kept,
    # +inbound_enabled+, and inbound sync on (WarpEngine::Sync.inbound?).
    def accepts_inbound? = deleted_at.nil? && inbound_enabled && Sync.inbound?

    # Issues a new +sync+ token owned by this peer, revokes the one before,
    # and remembers it as +inbound_token+. Returns the token, whose
    # +plain_token+ is shown once.
    def issue_inbound_token!
      transaction do
        previous = inbound_token
        token = ApplicationToken.create!(name: "sync from #{label}", owner: self, scopes: [ ApplicationToken::SYNC_SCOPE ],
                                         unrestricted: true)
        update!(inbound_token: token)
        previous&.revoke!
        token
      end
    end

    # Records an outbound push that went through: +last_synced_at+ now, +last_error+ cleared.
    def synced!
      update_columns(last_synced_at: Time.current, last_error: nil)
    end

    # Records +message+ as the +last_error+.
    def failed!(message)
      update_columns(last_error: message.to_s.truncate(2000))
    end

    # Allows the token association in Ransack searches.
    def self.ransackable_associations(auth_object = nil) = []

    # Allows the plain columns, never the secret, in Ransack searches.
    def self.ransackable_attributes(auth_object = nil)
      %w[id label transport outbound_enabled inbound_enabled created_by_type created_by_id last_synced_at created_at updated_at]
    end

    private

    def transport_is_known
      errors.add(:transport, "is not a registered sync transport (#{Sync::Transports.keys.join(', ')})") if transport_class.nil?
    end

    def transport_options_are_complete
      transport_class&.errors_for(self)&.each { |message| errors.add(:base, message) }
    end

    def allowed_channels_are_known
      unknown = channels - WarpEngine::ReleaseChannel::ALL
      errors.add(:allowed_channels, "has unknown channels #{unknown.join(', ')} (#{WarpEngine::ReleaseChannel::ALL.join(', ')})") if unknown.any?
    end

    ActiveSupport.run_load_hooks(:warp_engine_sync_peer, self)
  end
end
