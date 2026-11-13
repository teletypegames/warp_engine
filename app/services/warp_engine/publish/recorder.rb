module WarpEngine
  module Publish
    # Writes the catalog records of a publish in one transaction. Every write
    # restores a soft-deleted record instead of creating a second one.
    class Recorder
      # The label of the external link the metadata's +site+ becomes.
      SITE_LABEL = "Source Code".freeze
      # The label of the external link the metadata's +repo+ becomes.
      REPO_LABEL = "Repository".freeze

      # [definition] the WarpEngine::Platform::Definition of the platform
      def initialize(definition)
        @definition = definition
      end

      # Creates or updates the WarpEngine::Software named in +metadata+ (its
      # +site+ and +repo+ become external links), creates the
      # WarpEngine::Release +version+ when new, writes a WarpEngine::ReleaseAsset
      # for every <tt>kind => path</tt> of +assets+ and soft-deletes the assets
      # of kinds the platform no longer publishes.
      #
      # Returns the WarpEngine::Release. Raises ActiveRecord::RecordInvalid when a
      # record does not save.
      def record(metadata, version, assets)
        attributes = metadata.except(:site, :repo).merge(platform: @definition.name)
        ActiveRecord::Base.transaction do
          software = restore(WarpEngine::Software.find_or_initialize_by(name: attributes[:name]), attributes.except(:name))
          { SITE_LABEL => metadata[:site], REPO_LABEL => metadata[:repo] }.each do |label, url|
            next if url.blank?

            restore(WarpEngine::ExternalLink.find_or_initialize_by(software_id: software.id, label: label), url: url)
          end

          release = WarpEngine::Release.find_or_create_by!(software_id: software.id, version: version)
          assets.each do |kind, path|
            restore(WarpEngine::ReleaseAsset.find_or_initialize_by(release_id: release.id, kind: kind), path: path)
          end
          WarpEngine::ReleaseAsset.kept.where(release_id: release.id).where.not(kind: @definition.expected_kinds)
                                  .find_each(&:soft_delete!)
          release
        end
      end

      private

      def restore(record, attributes)
        record.assign_attributes(attributes.merge(deleted_at: nil))
        record.save!
        record
      end
    end
  end
end
