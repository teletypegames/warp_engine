require "digest"

module WarpEngine
  class ApplicationToken < ApplicationRecord
    self.table_name = "application_tokens"

    UPDATE_SCOPE = "update".freeze
    UPLOAD_SCOPE = "upload".freeze

    # A generált token csak létrehozáskor, memóriában érhető el — a DB-ben
    # kizárólag a SHA256 digest és a nem-titkos prefix tárolódik.
    attr_reader :plain_token

    belongs_to :owner, polymorphic: true

    default_scope { where(deleted_at: nil) }
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    before_validation :assign_owner_type, on: :create
    before_validation :generate_token, on: :create
    after_initialize { self.scopes = [] if new_record? && scopes.nil? }

    validates :name, presence: true
    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :scopes, presence: true
    validate :owner_type_matches_configuration

    def self.digest(token)
      Digest::SHA256.hexdigest(token)
    end

    # Az élő (nem törölt, nem lejárt), a kért scope-pal rendelkező token, különben nil.
    def self.authenticate(token, required_scope: nil)
      return nil if token.blank?

      record = active.find_by(token_digest: digest(token))
      return nil if record.nil?
      return nil if required_scope.present? && !Array(record.scopes).include?(required_scope)

      record
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Visszavonás = soft delete, az audit-nyom megmarad.
    def revoke!
      update_column(:deleted_at, Time.current)
    end

    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    # Admin form: vesszővel elválasztott scope-lista
    def scopes_string
      Array(scopes).join(", ")
    end

    def scopes_string=(value)
      self.scopes = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[created_at deleted_at expires_at id last_used_at name owner_id owner_type token_prefix unrestricted updated_at]
    end

    # A polimorf owner asszociációra a Ransack nem tud szűrni.
    def self.ransackable_associations(auth_object = nil)
      []
    end

    private

    def assign_owner_type
      self.owner_type = WarpEngine.config.application_token_owner_class if owner_type.blank?
    end

    def generate_token
      return if token_digest.present?

      @plain_token = SecureRandom.hex(24)
      self.token_prefix = @plain_token.first(8)
      self.token_digest = self.class.digest(@plain_token)
    end

    def owner_type_matches_configuration
      expected = WarpEngine.config.application_token_owner_class
      if expected.blank?
        errors.add(:base, "application_token_owner_class is not configured")
      elsif owner_type != expected
        errors.add(:owner_type, "must be #{expected}")
      end
    end

    ActiveSupport.run_load_hooks(:warp_engine_application_token, self)
  end
end
