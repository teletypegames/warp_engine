module WarpEngine
  # The steps of a publish, each its own object: Collector finds the assets,
  # MetadataReader reads the metadata, Recorder writes the catalog records, and
  # Publisher runs them in order for one platform.
  module Publish
    # Publishes an upload of one platform.
    class Publisher
      # [definition] the WarpEngine::Platform::Definition
      # [metadata]   overrides the definition's metadata reader (a callable
      #              taking the Upload); used by legacy platform services
      def initialize(definition, metadata: nil)
        @definition = definition
        @metadata = metadata || definition.metadata
      end

      # Publishes the upload <tt>name-version</tt> found in the file container:
      # collects the assets, checks the required kinds, reads the metadata and
      # records the catalog.
      #
      # Returns the WarpEngine::Release. Raises
      # WarpEngine::Platforms::MissingAssetsError when a required kind is
      # missing, and ActiveRecord::RecordInvalid when a record does not save.
      def publish(name, version)
        upload = Upload.new(name: name, version: version, root: WarpEngine.config.file_container_path)
        assets = Collector.new(@definition).collect(upload)
        missing = @definition.required_kinds - assets.keys
        raise WarpEngine::Platforms::MissingAssetsError.new(upload.versioned, missing) if missing.any?

        Recorder.new(@definition).record(MetadataReader.read(@metadata, upload), version, assets)
      end
    end
  end
end
