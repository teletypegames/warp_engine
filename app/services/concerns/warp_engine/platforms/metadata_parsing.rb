require "json"

module WarpEngine
  module Platforms
    module MetadataParsing
      METADATA_KEYS = %i[name title author desc site repo license].freeze

      private

      def parse_json_metadata(path)
        raw = JSON.parse(File.read(path), symbolize_names: true)
        raw.slice(*METADATA_KEYS)
      end
    end
  end
end
