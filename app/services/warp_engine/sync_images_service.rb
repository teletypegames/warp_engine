require "digest"

module WarpEngine
  # Sets a software's gallery from a manifest another engine (or the CI)
  # sends through <tt>POST /build/images</tt>: the images are named by their
  # SHA-256, so what the gallery has is kept and only reordered, and the
  # files it lacks come one by one through <tt>POST /build/images/upload</tt>
  # (#add). See WarpEngine::Sync::Transports::Http#deliver_images.
  class SyncImagesService
    # The manifest is not an Array of entries with a 64 hex digit sha256.
    class InvalidManifest < WarpEngine::Error; end

    # The uploaded file's digest is not the one it was sent with.
    class DigestMismatch < WarpEngine::Error; end

    # One manifest entry: the image's +sha256+, +filename+, +content_type+
    # and whether it is the +default+ one.
    Entry = ::Data.define(:sha256, :filename, :content_type, :default)

    # What #apply did: whether the gallery now follows the manifest
    # (+applied+), else the digests of the images to upload first (+missing+).
    Outcome = ::Data.define(:applied, :missing)

    # The pattern of a SHA-256 hex digest.
    SHA256 = /\A[0-9a-f]{64}\z/

    # Returns the Entry list of +raw+ (an Array of Hashes with +sha256+,
    # +filename+, +contentType+, +default+; string or symbol keys). Raises
    # InvalidManifest.
    def self.entries(raw)
      raise InvalidManifest, "images must be an array" unless raw.is_a?(Array)

      raw.map do |item|
        item = item.to_h.stringify_keys
        sha = item["sha256"].to_s.downcase
        raise InvalidManifest, "every image needs a sha256 (64 hex digits)" unless sha.match?(SHA256)

        Entry.new(sha256: sha, filename: item["filename"].to_s, content_type: item["contentType"].to_s,
                  default: [ true, "true", "1" ].include?(item["default"]))
      end
    end

    # Makes the gallery of +software+ follow +entries+ (Entry values, in
    # order): when it has every image by digest, sets their positions and the
    # default, marks them with +origin+ (+sync+ or +local+), and unlinks the
    # images +entries+ do not name; otherwise changes nothing. Returns an
    # Outcome naming the digests it lacks.
    def apply(software, entries, origin:)
      links = software.software_images.ordered.to_a
      by_sha = links.each_with_object({}) { |link, map| (sha = link.sha256) && map[sha] ||= link }
      missing = entries.map(&:sha256).uniq - by_sha.keys
      return Outcome.new(applied: false, missing: missing) if missing.any?

      SoftwareImage.transaction do
        kept = entries.uniq(&:sha256).each_with_index.map do |entry, index|
          by_sha[entry.sha256].tap { |link| link.update!(position: index, is_default: entry.default, origin: origin) }
        end
        (links - kept).each(&:destroy!)
      end
      Outcome.new(applied: true, missing: [])
    end

    # Adds the uploaded file +upload+ (an ActionDispatch::Http::UploadedFile)
    # to the image library and to the end of +software+'s gallery with
    # +origin+, unless an image with the digest +sha256+ is there already.
    # Returns the WarpEngine::SoftwareImage. Raises DigestMismatch when the
    # file is not +sha256+, ActiveRecord::RecordInvalid when it does not save.
    def add(software, upload, sha256:, origin:)
      sha = sha256.to_s.downcase
      existing = software.software_images.to_a.find { |link| link.sha256 == sha }
      return existing if existing

      digest = Digest::SHA256.file(upload.tempfile.path).hexdigest
      raise DigestMismatch, "SHA256 mismatch" unless ActiveSupport::SecurityUtils.secure_compare(digest, sha)

      SoftwareImage.create!(software: software, file_upload: upload, origin: origin,
                            position: software.software_images.maximum(:position).to_i + 1)
    end
  end
end
