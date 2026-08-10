module WarpEngine
  class DownloadService
    def self.container_base
      WarpEngine.config.file_container_path
    end

    # Lazy: a container path csak az első használatkor kötelező, boot/teszt közben nem.
    def self.base_path
      Pathname.new(container_base).realpath
    end

    # A letöltés helyét adja vissza (fájl vagy aláírt URL) és naplózza a
    # letöltést. A hely feloldása a storage adapteren megy — alapból :local,
    # tehát változatlanul lemezről.
    def locate(path:, ip:, user_agent:, referer:)
      relative = path.to_s
      return nil unless storage.file?(relative)

      log_download(relative, ip: ip, user_agent: user_agent, referer: referer)

      storage.locate(relative, filename: File.basename(relative))
    end

    # Visszafelé kompatibilis felület: az abszolút fájlútvonalat adja vissza
    # (vagy nil-t). Nem lemezes adapternél nincs útvonal — ott a #locate való.
    def create(path:, ip:, user_agent:, referer:)
      location = locate(path: path, ip: ip, user_agent: user_agent, referer: referer)
      return nil if location.nil?

      location.file? ? location.path : nil
    end

    private

    def storage
      WarpEngine.storage
    end

    def log_download(relative, ip:, user_agent:, referer:)
      escaped = relative.gsub("%", "\\%").gsub("_", "\\_")
      asset = WarpEngine::ReleaseAsset.find_by(path: File.join(self.class.container_base, relative)) ||
              WarpEngine::ReleaseAsset.where("path LIKE ?", "%#{escaped}%").first

      WarpEngine::Download.create!(
        file_path: relative,
        release: asset&.release,
        ip_address: ip,
        user_agent: user_agent&.truncate(500),
        referer: referer&.truncate(500)
      )
    end
  end
end
