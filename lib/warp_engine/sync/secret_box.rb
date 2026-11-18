module WarpEngine
  module Sync
    # Encrypts the tokens of the sync servers for the database, with a key
    # derived from the host's +secret_key_base+, so a database dump alone does
    # not give them away.
    module SecretBox
      # The salt the key is derived with.
      SALT = "warp_engine sync server secret".freeze

      module_function

      # Returns +plain+ encrypted and signed, as a string; +nil+ for a blank +plain+.
      def encrypt(plain)
        return nil if plain.blank?

        encryptor.encrypt_and_sign(plain.to_s)
      end

      # Returns the plain text of +sealed+, or +nil+ when it is blank or does
      # not open with the current key (the +secret_key_base+ changed).
      def decrypt(sealed)
        return nil if sealed.blank?

        encryptor.decrypt_and_verify(sealed.to_s)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      # Returns the ActiveSupport::MessageEncryptor of the derived key.
      def encryptor
        key = Rails.application.key_generator.generate_key(SALT, ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end
  end
end
