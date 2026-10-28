module WarpEngine
  # One device authorization grant (table +device_grants+): a client without
  # a browser asks for a sign-in, gets a +device_code+ to poll with and a
  # short +user_code+ the person enters on the verification page.
  #
  # Both codes are generated on create and +expires_at+ is set from the host's
  # +device_code_ttl+. When the person approves, +subject+ is the account and
  # +application_token+ the token issued to the device; +issued_token+ holds
  # the plain token until the device collects it or the grant expires.
  class DeviceGrant < ApplicationRecord
    self.table_name = "device_grants"

    # Characters a user code is drawn from: capital letters and digits, without
    # the easily confused I, O, 0 and 1.
    USER_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".freeze
    # Number of characters in a user code.
    USER_CODE_LENGTH   = 8

    belongs_to :application_token, class_name: "WarpEngine::ApplicationToken", optional: true
    belongs_to :subject, polymorphic: true, optional: true

    validates :device_code, presence: true, uniqueness: true
    validates :user_code, presence: true, uniqueness: true
    validates :expires_at, presence: true

    scope :pending, -> { where(approved_at: nil, denied_at: nil).where(expires_at: Time.current..) }

    before_validation :generate_codes, on: :create
    before_validation :set_expiry, on: :create

    # Finds the pending (unanswered, unexpired) grant for the user +code+ as a
    # person typed it; case, spaces and dashes do not matter. Returns the
    # WarpEngine::DeviceGrant or +nil+.
    def self.find_pending_by_user_code(code)
      pending.find_by(user_code: normalize_user_code(code))
    end

    # Returns +code+ upper-cased with everything but letters and digits removed.
    def self.normalize_user_code(code)
      code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    # Returns whether +expires_at+ has passed.
    def expired? = expires_at <= Time.current
    # Returns whether the person approved the sign-in.
    def approved? = approved_at.present?
    # Returns whether the person denied the sign-in.
    def denied? = denied_at.present?

    # Returns the grant's state: <tt>:denied</tt>, <tt>:approved</tt>,
    # <tt>:expired</tt> or <tt>:pending</tt>, checked in that order.
    def state
      return :denied if denied?
      return :approved if approved?
      return :expired if expired?

      :pending
    end

    # Returns the user code in groups of four joined by a dash, e.g.
    # <tt>ABCD-EFGH</tt>.
    def formatted_user_code
      user_code.to_s.scan(/.{1,4}/).join("-")
    end

    # Clears the uncollected plain +issued_token+ of every expired grant.
    # Returns the number of grants updated.
    def self.sweep_expired!
      where(expires_at: ...Time.current).where.not(issued_token: nil).update_all(issued_token: nil)
    end

    # Allows no association in Ransack searches.
    def self.ransackable_associations(auth_object = nil)
      []
    end

    private

    def generate_codes
      self.device_code = SecureRandom.hex(32) if device_code.blank?
      self.user_code = generate_user_code if user_code.blank?
    end

    def generate_user_code
      10.times do
        candidate = Array.new(USER_CODE_LENGTH) { USER_CODE_ALPHABET.chars.sample }.join
        return candidate unless self.class.exists?(user_code: candidate)
      end
      raise "could not generate a free device user code"
    end

    def set_expiry
      self.expires_at ||= WarpEngine.config.device_code_ttl.to_i.seconds.from_now
    end

    ActiveSupport.run_load_hooks(:warp_engine_device_grant, self)
  end
end
