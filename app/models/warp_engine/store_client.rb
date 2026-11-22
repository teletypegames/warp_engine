module WarpEngine
  # What a host sets for one of the store engines it serves (table
  # +store_clients+; WarpEngine::StoreClients): every field is optional, a
  # blank one takes the default WarpEngine::StoreClientService works out.
  #
  # [client]         the store engine, a WarpEngine::StoreClients key; unique
  # [software_name]  the catalog software the engine is released as
  # [name]           the store's name on the machine
  # [store_key]      the store id: the folder and file names on the machine
  # [subfolder]      the folder the games go into
  # [statuses]       the software statuses the store installs
  # [logo_urls]      the store's logo: image URLs ending in .png or .svg
  # [pinned_version] the engine release every machine runs, instead of the
  #                  newest stable one: a rollback for all of them at once
  class StoreClient < ApplicationRecord
    self.table_name = "store_clients"

    # The form a store id takes: lowercase letters, digits and dashes.
    STORE_KEY = /\A[a-z0-9][a-z0-9-]*\z/
    # The extensions a store logo may have.
    LOGO = %r{\Ahttps?://\S+\.(png|svg)\z}i

    validates :client, presence: true, uniqueness: true, inclusion: { in: ->(_) { WarpEngine::StoreClients.keys } }
    validates :store_key, format: { with: STORE_KEY }, allow_blank: true
    validates :subfolder, format: { with: %r{\A[^/]+\z} }, allow_blank: true
    validate :statuses_are_known
    validate :logos_are_images

    # Sets the statuses from a list, dropping blank entries (a form sends one).
    def statuses=(value)
      super(Array(value).map(&:to_s).compact_blank.presence)
    end

    # Sets the logo URLs from a list, or from a String with one URL per line.
    def logo_urls=(value)
      list = value.is_a?(String) ? value.split(/\s+/) : Array(value)
      super(list.map(&:to_s).compact_blank.presence)
    end

    # Returns the record of +client+, or a new unsaved one.
    def self.for(client) = find_or_initialize_by(client: client.to_s)

    private

    def statuses_are_known
      return if statuses.blank?

      unknown = Array(statuses).map(&:to_s) - WarpEngine::SoftwareStatus.keys
      errors.add(:statuses, "has unknown statuses: #{unknown.join(', ')}") if unknown.any?
    end

    def logos_are_images
      bad = Array(logo_urls).reject { |url| url.to_s.match?(LOGO) }
      errors.add(:logo_urls, "takes http(s) URLs of .png or .svg images: #{bad.join(', ')}") if bad.any?
    end
  end
end
