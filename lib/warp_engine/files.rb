require "fileutils"
require "zlib"

module WarpEngine
  # File helpers the engine's writers share: replacing a file or a directory
  # in one rename, and CRC32 checksums read in chunks.
  module Files
    # The read size of the checksum and copy loops, in bytes.
    CHUNK = 64 * 1024

    module_function

    # Yields a temporary path next to +target+ (<tt>target.NEW</tt>), then
    # renames it over +target+, so a reader sees the old or the new content and
    # never a half-written one. The temporary file or directory is removed when
    # the block raises.
    #
    #   WarpEngine::Files.atomic(path) { |temporary| File.write(temporary, text) }
    #
    # Returns the value of the block.
    def atomic(target)
      temporary = "#{target}.NEW"
      FileUtils.rm_rf(temporary)
      result = yield temporary
      File.rename(temporary, target)
      result
    ensure
      FileUtils.rm_rf(temporary) if temporary && File.exist?(temporary)
    end

    # Copies the file +source+ to +target+ through #atomic. Returns the CRC32 of
    # the content as eight lowercase hex digits.
    def copy_with_crc(source, target)
      atomic(target) do |temporary|
        crc = 0
        File.open(source, "rb") do |input|
          File.open(temporary, "wb") do |output|
            while (chunk = input.read(CHUNK))
              crc = Zlib.crc32(chunk, crc)
              output.write(chunk)
            end
          end
        end
        hex(crc)
      end
    end

    # Returns the CRC32 of the file at +path+ as eight lowercase hex digits.
    def crc32(path)
      crc = 0
      File.open(path, "rb") do |input|
        while (chunk = input.read(CHUNK))
          crc = Zlib.crc32(chunk, crc)
        end
      end
      hex(crc)
    end

    # Returns +crc+ as eight lowercase hex digits.
    def hex(crc) = format("%08x", crc)
  end
end
