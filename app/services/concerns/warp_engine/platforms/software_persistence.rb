module WarpEngine
  module Platforms
    # Mixin of the platform services (through Updatable): writes the catalog
    # records of a publish. Every writer restores a soft-deleted record instead of
    # creating a second one.
    module SoftwarePersistence
      private

      # Finds the WarpEngine::Software by <tt>attrs[:name]</tt> (or builds one),
      # assigns the other attributes, clears +deleted_at+ and saves it. Returns the
      # software; raises ActiveRecord::RecordInvalid when it does not validate.
      def update_or_create_software(attrs)
        software = WarpEngine::Software.find_or_initialize_by(name: attrs[:name])
        software.assign_attributes(attrs.except(:name))
        software.deleted_at = nil
        software.save!
        software
      end

      # Sets the URL of the WarpEngine::ExternalLink labelled +label+ on the
      # software +software_id+, creating or restoring the link. Raises
      # ActiveRecord::RecordInvalid when it does not validate.
      def upsert_external_link(software_id, label, url)
        link = WarpEngine::ExternalLink.find_or_initialize_by(software_id: software_id, label: label)
        link.url = url
        link.deleted_at = nil
        link.save!
      end

      # Returns the WarpEngine::Release matching <tt>attrs[:software_id]</tt> and
      # <tt>attrs[:version]</tt>, creating it from +attrs+ when there is none.
      def create_release_if_not_exists(attrs)
        existing = WarpEngine::Release.find_by(software_id: attrs[:software_id], version: attrs[:version])
        return existing if existing

        WarpEngine::Release.create!(attrs)
      end

      # Writes one WarpEngine::ReleaseAsset of +release+ for every <tt>kind => path</tt>
      # pair of +kind_paths+, updating the path of an existing (or soft-deleted) one.
      def sync_release_assets(release, kind_paths)
        kind_paths.each do |kind, path|
          asset = WarpEngine::ReleaseAsset.find_or_initialize_by(release_id: release.id, kind: kind)
          asset.path = path
          asset.deleted_at = nil
          asset.save!
        end
      end

      # Soft-deletes the kept assets of +release+ whose kind is not among
      # +expected_kinds+.
      def discard_unexpected_assets(release, expected_kinds)
        WarpEngine::ReleaseAsset.kept.where(release_id: release.id).where.not(kind: expected_kinds).find_each(&:soft_delete!)
      end
    end
  end
end
