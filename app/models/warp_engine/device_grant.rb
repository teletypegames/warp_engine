module WarpEngine

  class DeviceGrant < ApplicationRecord
    self.table_name = "device_grants"

    USER_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".freeze
    USER_CODE_LENGTH   = 8

    belongs_to :application_token, class_name: "WarpEngine::ApplicationToken", optional: true
    belongs_to :subject, polymorphic: true, optional: true

    validates :device_code, presence: true, uniqueness: true
    validates :user_code, presence: true, uniqueness: true
    validates :expires_at, presence: true

    scope :pending, -> { where(approved_at: nil, denied_at: nil).where(expires_at: Time.current..) }

    before_validation :generate_codes, on: :create
    before_validation :set_expiry, on: :create

    def self.find_pending_by_user_code(code)
      pending.find_by(user_code: normalize_user_code(code))
    end

    def self.normalize_user_code(code)
      code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    def expired? = expires_at <= Time.current
    def approved? = approved_at.present?
    def denied? = denied_at.present?

    def state
      return :denied if denied?
      return :approved if approved?
      return :expired if expired?

      :pending
    end

    def formatted_user_code
      user_code.to_s.scan(/.{1,4}/).join("-")
    end

    def self.sweep_expired!
      where(expires_at: ...Time.current).where.not(issued_token: nil).update_all(issued_token: nil)
    end

    def self.ransackable_associations(auth_object = nil)
      []
    end

    private

    def generate_codes
      self.device_code = SecureRandom.hex(32) if device_code.blank?
      self.user_code = self.class.generate_user_code if user_code.blank?
    end

    def self.generate_user_code

      10.times do
        candidate = Array.new(USER_CODE_LENGTH) { USER_CODE_ALPHABET.chars.sample }.join
        return candidate unless exists?(user_code: candidate)
      end
      raise "could not generate a free device user code"
    end

    def set_expiry
      self.expires_at ||= WarpEngine.config.device_code_ttl.to_i.seconds.from_now
    end

    ActiveSupport.run_load_hooks(:warp_engine_device_grant, self)
  end
end
