require "json"

module WarpEngine
  module Platforms
    # Mixin of the platform services (through Updatable): reads the software
    # metadata of an upload, either from a <tt>metadata.json</tt> or from the
    # leading comment lines of a Lua source.
    module MetadataParsing
      # The metadata keys a publish takes over onto the WarpEngine::Software; every
      # other key is dropped.
      METADATA_KEYS = %i[name title author desc site repo license category shelf_name].freeze

      private

      # Reads the JSON file at +path+ and returns its METADATA_KEYS as a Hash with
      # symbol keys. Raises JSON::ParserError on invalid JSON and Errno::ENOENT
      # when the file is missing.
      def parse_json_metadata(path)
        raw = JSON.parse(File.read(path), symbolize_names: true)
        raw.slice(*METADATA_KEYS)
      end

      # Reads the <tt>-- key: value</tt> comment lines at the top of the Lua file at
      # +source_path+ (TIC-80 cartridge header style), stopping at the first line
      # that is not a comment. Returns the METADATA_KEYS found as a Hash with
      # downcased symbol keys and string values.
      def parse_lua_metadata(source_path)
        metadata = {}
        File.foreach(source_path) do |line|
          break unless line.start_with?("--")
          parts = line[2..].split(":", 2)
          next if parts.length != 2
          key   = parts[0].strip.downcase.to_sym
          value = parts[1].strip
          metadata[key] = value
        end
        metadata.slice(*METADATA_KEYS)
      end
    end
  end
end
