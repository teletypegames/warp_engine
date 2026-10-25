require "json"

module WarpEngine
  module Platforms
    module MetadataParsing
      METADATA_KEYS = %i[name title author desc site repo license category shelf_name].freeze

      private

      def parse_json_metadata(path)
        raw = JSON.parse(File.read(path), symbolize_names: true)
        raw.slice(*METADATA_KEYS)
      end

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
