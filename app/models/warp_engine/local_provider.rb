module WarpEngine
  # The state of one local provider (table +local_providers+): its +key+
  # (a WarpEngine::Local::Providers class), its +role+, its +state+ (one of
  # STATES), the +settings+ it stored (URLs, user names) and its +secrets+
  # (tokens, passwords), kept encrypted like a sync peer's secret
  # (WarpEngine::Sync::SecretBox), and the +last_error+.
  class LocalProvider < ApplicationRecord
    self.table_name = "local_providers"

    # The states: never started, starting, answering and set up, stopped, broken.
    STATES = %w[off starting ready stopped failed].freeze

    validates :key, presence: true, uniqueness: true
    validates :role, presence: true
    validates :state, inclusion: { in: STATES }

    scope :ready, -> { where(state: "ready") }

    # Returns the record of +key+, created (+off+) with the role of its class
    # when there is none. Raises ArgumentError for an unknown key.
    def self.for(key)
      klass = Local::Providers.find(key) or raise ArgumentError, "no local provider #{key}"
      find_or_create_by!(key: klass.key) { |record| record.role = klass.role.to_s }
    end

    # Returns the WarpEngine::Local::Provider working on this record.
    def provider = Local::Providers.find(key).new(self)

    # Returns +true+ while it answers and is set up.
    def ready? = state == "ready"

    # Returns the secrets as a Hash (empty when none are stored or they do not decrypt).
    def secrets
      plain = Sync::SecretBox.decrypt(self[:secrets])
      plain ? JSON.parse(plain) : {}
    rescue JSON::ParserError
      {}
    end

    # Stores +value+ (a Hash) encrypted.
    def secrets=(value)
      self[:secrets] = Sync::SecretBox.encrypt(JSON.generate(value.to_h))
    end

    # Records the state +state+ and the error +message+ (or none).
    def mark!(state, message = nil)
      update!(state: state, last_error: message&.to_s&.truncate(2000))
    end
  end
end
