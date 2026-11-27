require "json"

module WarpEngine
  module Publish
    # Reads the software metadata of an Upload. A platform names its reader
    # (WarpEngine::Platform::Definition +metadata+): +:json+ reads
    # <tt>name-version.metadata.json</tt>, +:lua+ the <tt>-- key: value</tt>
    # header comments of <tt>name-version.lua</tt> (the TIC-80 cartridge
    # style), overlaid by <tt>name-version.metadata.json</tt> when the upload
    # has one (for the keys a header cannot hold: +web+, +fork_of+), a
    # callable is called with the Upload.
    module MetadataReader
      # The metadata keys a publish takes over: onto the WarpEngine::Software,
      # except +web+, which goes to the release (Publish::WebBinder); every
      # other key is dropped.
      KEYS = %i[name title author desc site repo license category directory_name web
                forks_allowed fork_of_engine fork_of_name fork_of_version fork_of_repo].freeze

      # The old names of metadata keys, read as their new name when the new
      # one is not set: <tt>shelf_name</tt> is +directory_name+.
      ALIASES = { shelf_name: :directory_name }.freeze

      # The keys of the nested <tt>fork_of</tt> object a JSON metadata may use
      # instead of the flat +fork_of_*+ keys.
      FORK_OF_KEYS = %i[engine name version repo].freeze

      module_function

      # Returns the KEYS of +upload+'s metadata as a Hash with symbol keys, read
      # the way +reader+ (+:json+, +:lua+ or a callable) says. Raises
      # JSON::ParserError on invalid JSON and Errno::ENOENT when the file is
      # missing.
      def read(reader, upload)
        raw = case reader
        when :json, "json" then json(upload.path("#{upload.versioned}.metadata.json"))
        when :lua, "lua" then lua_with_json(upload)
        else reader.call(upload)
        end
        canonical(flatten_fork_of(raw.to_h.symbolize_keys)).slice(*KEYS)
      end

      # Returns +metadata+ (Symbol or String keys) with every ALIASES key
      # under its new name: <tt>directory_name || shelf_name</tt>. The new key
      # wins when both are set; the old key is removed.
      def canonical(metadata)
        strings = metadata.keys.first.is_a?(String)
        ALIASES.reduce(metadata) do |result, pair|
          old_key, new_key = strings ? pair.map(&:to_s) : pair
          next result unless result.key?(old_key)

          value = result[old_key]
          result = result.except(old_key)
          result[new_key].nil? ? result.merge(new_key => value) : result
        end
      end

      # Returns +metadata+ with a nested <tt>fork_of</tt> Hash spread into the
      # flat +fork_of_*+ keys (a flat key that is set wins).
      def flatten_fork_of(metadata)
        nested = metadata[:fork_of]
        return metadata unless nested.is_a?(Hash)

        spread = FORK_OF_KEYS.to_h { |key| [ :"fork_of_#{key}", nested[key] || nested[key.to_s] ] }.compact
        spread.merge(metadata.compact)
      end

      # Returns the Lua header of +upload+ (#lua) with the keys of its
      # <tt>name-version.metadata.json</tt> over it, when that file exists.
      def lua_with_json(upload)
        header = lua(upload.path("#{upload.versioned}.lua"))
        json_path = upload.path("#{upload.versioned}.metadata.json")
        File.exist?(json_path) ? header.merge(json(json_path)) : header
      end

      # Returns the JSON object in the file +path+, with symbol keys.
      def json(path) = JSON.parse(File.read(path), symbolize_names: true)

      # Returns the <tt>-- key: value</tt> lines at the top of the Lua file
      # +path+, up to the first line that is not a comment, with downcased
      # symbol keys and string values.
      def lua(path)
        File.foreach(path).take_while { |line| line.start_with?("--") }.each_with_object({}) do |line, metadata|
          key, value = line[2..].split(":", 2)
          metadata[key.strip.downcase.to_sym] = value.strip if value
        end
      end
    end
  end
end
