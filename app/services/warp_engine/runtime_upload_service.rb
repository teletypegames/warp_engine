require "digest"
require "fileutils"
require "tmpdir"
require "zip"

module WarpEngine
  # Installs a version of an uploaded WarpEngine::Runtime (one declared with
  # <tt>source :upload</tt>, e.g. the TIC-80 player taken from a Pro build)
  # from a zip a build sends to <tt>POST /build/runtime</tt>. The files the
  # runtime declares are taken from the zip (any other entry is ignored),
  # their SHA-256 digests recorded on the WarpEngine::RuntimeVersion, and the
  # files written under <tt>_runtimes/<name>-<version>/</tt>. A version is
  # immutable: sending it again with the same files changes nothing, with
  # other files it is refused.
  class RuntimeUploadService
    # Raised when the upload cannot be installed: unknown or downloaded
    # runtime, malformed version, unsafe or missing file.
    class Error < WarpEngine::Error; end

    # Raised when the version is installed already with other files.
    class Conflict < Error; end

    # The form a runtime version must have.
    VERSION_FORMAT = /\A[0-9A-Za-z][0-9A-Za-z._+-]{0,63}\z/

    # What an upload did.
    #
    # [runtime_version] the WarpEngine::RuntimeVersion
    # [created]         +false+ when the version was there with the same files
    Result = ::Data.define(:runtime_version, :created)

    # Installs the zip at +zip_path+ as the version +version+ of the runtime
    # +name+. Returns a Result. Raises Error or Conflict (see there). Writes
    # the files and the records.
    def upload(name:, version:, zip_path:)
      definition = definition_for(name)
      version = version.to_s
      raise Error, "malformed version #{version.inspect}" unless version.match?(VERSION_FORMAT)

      Dir.mktmpdir("warp_engine_runtime") do |dir|
        digests = extract(zip_path, dir, definition)
        existing = WarpEngine::RuntimeVersion.kept.find_by(name: name.to_s, version: version)
        if existing
          raise Conflict, "#{name} #{version} is installed with other files" unless existing.file_digests == digests

          return Result.new(existing, false)
        end

        Result.new(install(name.to_s, version, dir, digests), true)
      end
    end

    private

    def definition_for(name)
      runtime = WarpEngine::Runtime.find(name)
      raise Error, "unknown runtime #{name}" if runtime.nil?
      raise Error, "#{name} is downloaded, not uploaded" unless runtime.upload?

      runtime.definition
    end

    def extract(zip_path, dir, definition)
      digests = {}
      Zip::File.open(zip_path) do |zip|
        zip.each do |entry|
          next if entry.directory?

          file = entry.name.delete_prefix("./")
          next unless definition.files.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME) }
          raise Error, "unsafe path #{entry.name}" if file.start_with?("/") || file.split("/").include?("..")

          target = File.join(dir, file)
          FileUtils.mkdir_p(File.dirname(target))
          entry.extract(target) { true }
          digests[file] = Digest::SHA256.file(target).hexdigest
        end
      end
      missing = definition.files.reject { |glob| digests.keys.any? { |file| File.fnmatch?(glob, file, File::FNM_PATHNAME) } }
      raise Error, "the zip lacks #{missing.join(', ')}" if missing.any?

      digests.sort.to_h
    rescue Zip::Error => e
      raise Error, "not a zip: #{e.message}"
    end

    def install(name, version, dir, digests)
      directory = WarpEngine::Runtime.directory(name, version)
      target = File.join(WarpEngine.config.file_container_path, directory)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.rm_rf(target)
      WarpEngine::Files.atomic(target) { |temporary| FileUtils.cp_r(dir, temporary) }

      record = WarpEngine::RuntimeVersion.find_or_initialize_by(name: name, version: version)
      record.update!(source: "upload", path: directory, files: digests, deleted_at: nil,
                     size_bytes: digests.keys.sum { |file| File.size(File.join(target, file)) })
      record
    end
  end
end
