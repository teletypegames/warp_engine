require "digest"

module WarpEngine
  class ApplicationToken < ApplicationRecord
    self.table_name = "application_tokens"

    UPDATE_SCOPE = "update".freeze
    UPLOAD_SCOPE = "upload".freeze

    CATALOG_SCOPE = "catalog".freeze

    ADMIN_READ_SCOPE   = AdminApi::Scopes::READ
    ADMIN_WRITE_SCOPE  = AdminApi::Scopes::WRITE
    ADMIN_TOKENS_SCOPE = AdminApi::Scopes::TOKENS
    ADMIN_SCOPES       = AdminApi::Scopes::ALL

    include SoftDeletable

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

    def self.digest(token)
      Digest::SHA256.hexdigest(token)
    end

    def self.authenticate(token, required_scope: nil)
      return nil if token.blank?

      record = active.find_by(token_digest: digest(token))
      return nil if record.nil?
      return nil if required_scope.present? && !Array(record.scopes).include?(required_scope)

      record
    end

    def admin?
      Array(scopes).intersect?(ADMIN_SCOPES)
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def revoke!
      soft_delete!
    end

    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    def scopes_string
      Array(scopes).join(", ")
    end

    def scopes_string=(value)
      self.scopes = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

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
