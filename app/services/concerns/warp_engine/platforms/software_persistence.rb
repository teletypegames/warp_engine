module WarpEngine
  module Platforms
    module SoftwarePersistence
      private

      def update_or_create_software(attrs)
        software = WarpEngine::Software.find_or_initialize_by(name: attrs[:name])
        software.assign_attributes(attrs.except(:name))
        software.deleted_at = nil
        software.save!
        software
      end

      def upsert_external_link(software_id, label, url)
        link = WarpEngine::ExternalLink.find_or_initialize_by(software_id: software_id, label: label)
        link.url = url
        link.deleted_at = nil
        link.save!
      end

      def create_release_if_not_exists(attrs)
        existing = WarpEngine::Release.find_by(software_id: attrs[:software_id], version: attrs[:version])
        return existing if existing

        WarpEngine::Release.create!(attrs)
      end

      def sync_release_assets(release, kind_paths)
        kind_paths.each do |kind, path|
          asset = WarpEngine::ReleaseAsset.find_or_initialize_by(release_id: release.id, kind: kind)
          asset.path = path
          asset.deleted_at = nil
          asset.save!
        end
      end
    end
  end
end
