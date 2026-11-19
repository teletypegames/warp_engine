require "digest"

module WarpEngine
  module Sync
    # One image of a software's gallery as sync sends it: where its file is
    # (+path+), its +filename+ and +content_type+, its +sha256+ (the other side
    # keeps what it has by this) and whether it is the +default+ one.
    ImageFile = ::Data.define(:path, :filename, :content_type, :sha256, :default) do
      # Returns the images of +software+ in gallery order that have a file
      # here (WarpEngine::Images.file_path_for); an image adapter that keeps
      # no files yields none.
      def self.of(software)
        software.software_images.includes(:image).ordered.filter_map do |link|
          path = WarpEngine::Images.file_path_for(link.image_id)
          next nil if path.nil?

          record = link.image
          new(path: path, filename: record.try(:original_filename).presence || File.basename(path),
              content_type: record.try(:content_type).presence || "application/octet-stream",
              sha256: Digest::SHA256.file(path).hexdigest, default: link.is_default ? true : false)
        end
      end

      # Returns the manifest entry the other side reads: sha256, filename,
      # contentType and default.
      def to_manifest = { sha256: sha256, filename: filename, contentType: content_type, default: default }

      # Returns the name the file has in a mirror: its place (two digits),
      # the first 12 characters of its digest and its extension.
      def mirror_name(index) = format("%02d-%s%s", index + 1, sha256.first(12), File.extname(filename).downcase)
    end
  end
end
