module WarpEngine
  # The state of one local component (table +local_components+): its +key+
  # (a WarpEngine::Local::Components class), its +role+, its +state+ (one of
  # STATES), the +settings+ it stored (URLs, user names) and its +secrets+
  # (tokens, passwords), kept encrypted like a sync peer's secret
  # (WarpEngine::Sync::SecretBox), and the +last_error+.
  class LocalComponent < ApplicationRecord
    self.table_name = "local_components"

    # The states: never started, starting, answering and set up, stopped, broken.
    STATES = %w[off starting ready stopped failed].freeze

    validates :key, presence: true, uniqueness: true
    validates :role, presence: true
    validates :state, inclusion: { in: STATES }

    scope :ready, -> { where(state: "ready") }

    # Returns the record of +key+, created (+off+) with the role of its class
    # when there is none. Raises ArgumentError for an unknown key.
    def self.for(key)
      klass = Local::Components.find(key) or raise ArgumentError, "no local component #{key}"
      find_or_create_by!(key: klass.key) { |record| record.role = klass.role.to_s }
    end

    # Returns the WarpEngine::Local::Component working on this record.
    def component = Local::Components.find(key).new(self)

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
