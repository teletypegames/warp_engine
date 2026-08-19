module WarpEngine
  # One pending sign-in from a client that has no browser of its own.
  #
  # The shape is RFC 8628's device authorization grant, and the reason for it is that a
  # desktop client cannot host a login form without asking a person to type a password
  # into a window that is not a browser. So the client asks for a pair of codes, sends
  # the person to the host's own page with the short one, and polls with the long one
  # until somebody approves it.
  #
  # Short-lived by design: this row exists for the minute or two between "the client
  # asked" and "the person answered". What survives it is the ApplicationToken.
  class DeviceGrant < ApplicationRecord
    self.table_name = "device_grants"

    # No I, O, 0 or 1: this alphabet is read off one screen and typed into another, and
    # those four are where that goes wrong.
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

    # Typed by a person, so it arrives with whatever case and separators they used.
    def self.normalize_user_code(code)
      code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    def expired? = expires_at <= Time.current
    def approved? = approved_at.present?
    def denied? = denied_at.present?

    # What the polling client is told. Order matters: a denied grant is denied even
    # after it expires, because "somebody said no" is the more useful answer.
    def state
      return :denied if denied?
      return :approved if approved?
      return :expired if expired?

      :pending
    end

    # Grouped for reading aloud and for typing: WARP-K7M2.
    def formatted_user_code
      user_code.to_s.scan(/.{1,4}/).join("-")
    end

    # Housekeeping for a host that wants it: an expired grant has nothing left to give,
    # and its issued_token would be a live secret nobody is waiting for.
    def self.sweep_expired!
      where(expires_at: ...Time.current).where.not(issued_token: nil).update_all(issued_token: nil)
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[approved_at client_name created_at denied_at expires_at id subject_id subject_type updated_at user_code]
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
      # Retried rather than trusted: the alphabet is small enough that a collision is
      # a real, if rare, event, and a unique index would turn it into a 500.
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
