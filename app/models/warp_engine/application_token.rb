require "digest"

module WarpEngine
  # A bearer credential (table +application_tokens+). Only the SHA-256 digest
  # and the first eight characters (+token_prefix+) are stored; the plain token
  # exists only on the instance that created it (#plain_token).
  #
  # +scopes+ says what the token may do: +update+ and +upload+ for the CI's
  # <tt>/build</tt> endpoints, +catalog+ for a signed-in client, and the
  # Admin API scopes. The polymorphic +owner+ must be of a class the host
  # configured (application token, access token or Admin API owner class), and
  # admin scopes need the Admin API owner class. An +unrestricted+ token is
  # exempt from software ownership checks. Revoking soft-deletes it
  # (WarpEngine::SoftDeletable); the +active+ scope holds the kept, unexpired
  # tokens.
  class ApplicationToken < ApplicationRecord
    self.table_name = "application_tokens"

    # Scope for <tt>POST /build/publish</tt> and triggering CI pipelines.
    UPDATE_SCOPE = "update".freeze
    # Scope for <tt>POST /build/upload</tt>.
    UPLOAD_SCOPE = "upload".freeze

    # Scope of a client signed in through the device grant, read by the catalog
    # API.
    CATALOG_SCOPE = "catalog".freeze

    # Admin API read scope (WarpEngine::AdminApi::Scopes::READ).
    ADMIN_READ_SCOPE   = AdminApi::Scopes::READ
    # Admin API write scope (WarpEngine::AdminApi::Scopes::WRITE).
    ADMIN_WRITE_SCOPE  = AdminApi::Scopes::WRITE
    # Admin API token management scope (WarpEngine::AdminApi::Scopes::TOKENS).
    ADMIN_TOKENS_SCOPE = AdminApi::Scopes::TOKENS
    # Every Admin API scope (WarpEngine::AdminApi::Scopes::ALL).
    ADMIN_SCOPES       = AdminApi::Scopes::ALL

    include SoftDeletable

    # The plain token, set only on the instance that generated it on create;
    # +nil+ on records loaded from the database.
    attr_reader :plain_token

    belongs_to :owner, polymorphic: true

    scope :active, -> { kept.where("expires_at IS NULL OR expires_at > ?", Time.current) }

    before_validation :assign_owner_type, on: :create
    before_validation :generate_token, on: :create
    after_initialize { self.scopes = [] if new_record? && scopes.nil? }

    validates :name, presence: true
    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :scopes, presence: true
    validate :owner_type_matches_configuration
    validate :admin_scopes_need_admin_owner

    # Returns the SHA-256 hex digest of +token+, the form stored in
    # +token_digest+.
    def self.digest(token)
      Digest::SHA256.hexdigest(token)
    end

    # Finds the active token whose digest matches the plain +token+.
    #
    # [required_scope] a scope the token must carry, or +nil+ for any
    #
    # Returns the WarpEngine::ApplicationToken, or +nil+ when +token+ is blank,
    # unknown, revoked, expired or lacks the scope.
    def self.authenticate(token, required_scope: nil)
      return nil if token.blank?

      record = active.find_by(token_digest: digest(token))
      return nil if record.nil?
      return nil if required_scope.present? && !Array(record.scopes).include?(required_scope)

      record
    end

    # Returns whether the token carries any Admin API scope.
    def admin?
      Array(scopes).intersect?(ADMIN_SCOPES)
    end

    # Returns whether +expires_at+ is set and has passed.
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Revokes the token by soft-deleting it.
    def revoke!
      soft_delete!
    end

    # Sets +last_used_at+ to now, without validations or callbacks.
    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    # Returns the scopes as a comma-separated string, for forms.
    def scopes_string
      Array(scopes).join(", ")
    end

    # Sets +scopes+ from a comma-separated string, stripped, without blanks and
    # duplicates.
    def scopes_string=(value)
      self.scopes = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

    # Allows no association in Ransack searches.
    def self.ransackable_associations(auth_object = nil)
      []
    end

    private

    def assign_owner_type
      self.owner_type = WarpEngine.config.application_token_owner_class if owner_type.blank?
    end

    def permitted_owner_types
      [ WarpEngine.config.application_token_owner_class,
        WarpEngine.config.access_token_owner_class,
        admin_owner_type ].compact_blank.uniq
    end

    def admin_owner_type
      WarpEngine.config.admin_api.owner_class_name
    end

    def admin_scopes_need_admin_owner
      return unless admin?
      return if admin_owner_type.present? && owner_type == admin_owner_type

      errors.add(:scopes, "admin scopes need an owner of #{admin_owner_type.presence || 'the admin owner class'}")
    end

    def generate_token
      return if token_digest.present?

      @plain_token = SecureRandom.hex(24)
      self.token_prefix = @plain_token.first(8)
      self.token_digest = self.class.digest(@plain_token)
    end

    def owner_type_matches_configuration
      permitted = permitted_owner_types
      if permitted.empty?
        errors.add(:base, "application_token_owner_class is not configured")
      elsif !permitted.include?(owner_type)
        errors.add(:owner_type, "must be #{permitted.join(' or ')}")
      end
    end

    ActiveSupport.run_load_hooks(:warp_engine_application_token, self)
  end
end
