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
      # earlier publish of the same version left; a kind with alternative
      # extensions takes the first of them that is there.
      def collect(upload)
        @definition.kind_specs.each_with_object({}) do |spec, found|
          if spec.kind.unpacked?
            asset = upload.path(spec.asset_name(upload.versioned))
            zip = upload.path(spec.upload_name(upload.versioned))
            @unpacker.replace_dir(zip, asset) if File.file?(zip)
            found[spec.name] = asset if File.directory?(asset)
          else
            asset = spec.asset_names(upload.versioned).map { |name| upload.path(name) }.find { |path| File.file?(path) }
            found[spec.name] = asset if asset
          end
        end
      end
    end
  end
end
