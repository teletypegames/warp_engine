module WarpEngine
  # Another WarpEngine the releases are pushed to (table +sync_servers+): a
  # +label+, the +host+ (its base URL with the mount, <tt>https://</tt> outside
  # development and test) and the +secret+, a token with the +sync+ scope that
  # engine issued. The secret is stored encrypted (WarpEngine::Sync::SecretBox)
  # with its first eight characters in +secret_prefix+; an empty secret on an
  # update keeps the stored one. +active+ turns a server off without deleting
  # it; +last_synced_at+ and +last_error+ tell how its last push went.
  # Soft-deletable; the +active+ scope holds the kept, active servers.
  class SyncServer < ApplicationRecord
    self.table_name = "sync_servers"

    include SoftDeletable

    has_many :sync_events, foreign_key: :sync_server_id, inverse_of: :sync_server

    scope :active, -> { kept.where(active: true) }

    validates :label, presence: true, length: { maximum: 128 }
    validates :host, presence: true, length: { maximum: 255 }
    validates :secret, presence: true
    validate :host_is_a_url

    # Returns the plain token, or +nil+ when none is stored or it does not
    # decrypt with the current key.
    def secret
      Sync::SecretBox.decrypt(self[:secret])
    end

    # Stores +value+ encrypted and keeps its prefix; a blank +value+ leaves the
    # stored secret as it is.
    def secret=(value)
      return if value.blank?

      self[:secret] = Sync::SecretBox.encrypt(value.to_s.strip)
      self.secret_prefix = value.to_s.strip.first(8)
    end

    # Returns the host without a trailing slash.
    def base_url = host.to_s.strip.chomp("/")

    # Returns a WarpEngine::Sync::Client for this server.
    def client = Sync::Client.new(host: base_url, secret: secret)

    # Records a push that went through: +last_synced_at+ now, +last_error+ cleared.
    def synced!
      update_columns(last_synced_at: Time.current, last_error: nil)
    end

    # Records +message+ as the +last_error+.
    def failed!(message)
      update_columns(last_error: message.to_s.truncate(2000))
    end

    # Allows no association in Ransack searches.
    def self.ransackable_associations(auth_object = nil) = []

    # Allows the plain columns, never the secret, in Ransack searches.
    def self.ransackable_attributes(auth_object = nil)
      %w[id label host active last_synced_at created_at updated_at]
    end

    private

    def host_is_a_url
      uri = URI.parse(base_url)
      return errors.add(:host, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
      return if uri.scheme == "https" || Rails.env.local?

      errors.add(:host, "must use https")
    rescue URI::InvalidURIError
      errors.add(:host, "must be an http(s) URL")
    end

    ActiveSupport.run_load_hooks(:warp_engine_sync_server, self)
  end
end
