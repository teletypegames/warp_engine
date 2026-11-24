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
      # +site+ becomes an external link, its +repo+ the +source+ link; a
      # +forks_allowed+ given as text is read as a boolean), creates the
      # WarpEngine::Release +version+ when new, writes a WarpEngine::ReleaseAsset
      # for every <tt>kind => path</tt> of +assets+ (the software's +app+ is
      # the variant of the definition, +nil+ without variants), soft-deletes the assets
      # of kinds the platform no longer publishes, and binds the release to
      # its web runtime from the metadata's +web+ section (Publish::WebBinder).
      #
      # Returns the WarpEngine::Release. Raises ActiveRecord::RecordInvalid when a
      # record does not save.
      def record(metadata, version, assets)
        attributes = software_attributes(metadata)
        ActiveRecord::Base.transaction do
          software = restore(WarpEngine::Software.find_or_initialize_by(name: attributes[:name]), attributes.except(:name))
          restore(WarpEngine::ExternalLink.find_or_initialize_by(software_id: software.id, label: SITE_LABEL), url: metadata[:site]) if metadata[:site].present?
          record_source(software, metadata[:repo]) if metadata[:repo].present?

          release = restore(WarpEngine::Release.find_or_initialize_by(software_id: software.id, version: version), {})
          assets.each do |kind, path|
            restore(WarpEngine::ReleaseAsset.find_or_initialize_by(release_id: release.id, kind: kind), path: path)
          end
          WarpEngine::ReleaseAsset.kept.where(release_id: release.id).where.not(kind: @definition.expected_kinds)
                                  .find_each(&:soft_delete!)
          WebBinder.new(WarpEngine::Platform.find(@definition.name, app: @definition.app)).bind(release, metadata[:web])
          release
        end
      end

      private

      def software_attributes(metadata)
        attributes = metadata.except(:site, :repo, :web).merge(platform: @definition.name, app: @definition.app)
        if attributes.key?(:forks_allowed)
          attributes[:forks_allowed] = ActiveModel::Type::Boolean.new.cast(attributes[:forks_allowed]) != false
        end
        attributes
      end

      def record_source(software, url)
        link = WarpEngine::ExternalLink.where(software_id: software.id).sources.order(deleted_at: :desc).first ||
               WarpEngine::ExternalLink.find_or_initialize_by(software_id: software.id, label: REPO_LABEL)
        WarpEngine::ExternalLink.kept.sources.where(software_id: software.id).where.not(id: link.id).find_each(&:soft_delete!)
        restore(link, url: url, kind: "source", label: link.label.presence || REPO_LABEL)
      end

      def restore(record, attributes)
        record.assign_attributes(attributes.merge(deleted_at: nil))
        record.save!
        record
      end
    end
  end
end
