module WarpEngine
  module Publish
    # Finds the asset of every kind a platform publishes in an Upload,
    # unpacking the zips of the kinds that are served unpacked.
    class Collector
      # [definition] the WarpEngine::Platform::Definition
      # [unpacker]   what unpacks the zips (an Unpacker)
      def initialize(definition, unpacker: Unpacker.new)
        @definition = definition
        @unpacker = unpacker
      end

      # Returns <tt>{ kind => absolute path }</tt> of the kinds present in
      # +upload+. An unpacked kind's zip is unpacked first, replacing what an
      # earlier publish of the same version left.
      def collect(upload)
        @definition.kind_specs.each_with_object({}) do |spec, found|
          asset = upload.path(spec.asset_name(upload.versioned))
          if spec.kind.unpacked?
            zip = upload.path(spec.upload_name(upload.versioned))
            @unpacker.replace_dir(zip, asset) if File.file?(zip)
            found[spec.name] = asset if File.directory?(asset)
          elsif File.file?(asset)
            found[spec.name] = asset
          end
        end
      end
    end
  end
end
