module WarpEngine
  module Outlets
    class Shelf < Base
      # The <tt>INDEX.TXT</tt> of a shelf folder: reads the entries a previous
      # sync wrote and writes the new list in one rename.
      class IndexFile
        # The name of the index file in every shelf folder.
        NAME = "INDEX.TXT".freeze
        # The first line of the index: the format version and the field names.
        # Version 2 added the last two fields, so a version 1 reader that stops
        # after the description still reads the rest of the line right.
        HEADER = "#SHELF 2 file|version|size|crc32|title|author|description|category|preview".freeze

        # The absolute path of the index file.
        attr_reader :path

        # [directory] the absolute path of the shelf folder
        def initialize(directory)
          @path = File.join(directory, NAME)
        end

        # Returns the current text of the index, or +nil+ when there is none.
        def text = File.file?(path) ? File.read(path) : nil

        # Returns the entries of the current index as
        # <tt>{ file => { version:, size:, crc32: } }</tt>; empty without an index.
        def entries
          (text || "").each_line.with_object({}) do |line, index|
            next if line.start_with?("#")

            file, version, size, crc32 = line.chomp.split("|", 5)
            next if file.blank?

            index[file] = { version: version, size: size.to_i, crc32: crc32 }
          end
        end

        # Returns the index text of +entries+ (objects answering +line+): the
        # HEADER and one line each.
        def render(entries) = ([ HEADER ] + entries.map(&:line)).join("\n") + "\n"

        # Returns +true+ when #render of +entries+ differs from the current text.
        def changed?(entries) = render(entries) != text

        # Writes the index of +entries+ through WarpEngine::Files.atomic when it
        # changed. Returns whether it wrote.
        def write(entries)
          rendered = render(entries)
          return false if rendered == text

          WarpEngine::Files.atomic(path) { |temporary| File.write(temporary, rendered) }
          true
        end
      end
    end
  end
end
