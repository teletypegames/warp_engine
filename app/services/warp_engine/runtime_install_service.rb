require "digest"
require "fileutils"
require "net/http"

module WarpEngine
  # Installs a downloaded WarpEngine::Runtime into the file container: fetches
  # the base files and the components of a version from its pinned source,
  # checks every file against the SHA-256 the runtime's checksum list gives,
  # writes it under <tt>_runtimes/<name>-<version>/</tt> and records the
  # WarpEngine::RuntimeVersion with its components, with the runtime's licence
  # notice beside them (#notice!). A file already there with
  # the right digest is kept; existing files are never changed, so installing
  # again only adds what is missing.
  class RuntimeInstallService
    # Raised when a runtime cannot be installed: it is not a downloaded one,
    # the version or a component is unknown, a download fails or its digest
    # does not match.
    class Error < WarpEngine::Error; end

    # What an install did (or, on a dry run, would do).
    #
    # [runtime_version] the WarpEngine::RuntimeVersion (+nil+ on a dry run)
    # [name]            the runtime name
    # [version]         the version installed
    # [fetched]         the files downloaded (to be downloaded)
    # [kept]            the files already in place
    # [components]      the components installed, a Hash of kind to keys
    # [dry_run]         +true+ when nothing was written
    Result = ::Data.define(:runtime_version, :name, :version, :fetched, :kept, :components, :dry_run)

    # The fetcher used when none is given: a GET that follows up to five
    # redirects and returns the body; raises Error on any other answer.
    HTTP_FETCHER = lambda do |url, redirects = 5|
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      case response
      when Net::HTTPSuccess then response.body
      when Net::HTTPRedirection
        raise Error, "too many redirects for #{url}" if redirects.zero?

        HTTP_FETCHER.call(URI.join(url, response["location"]).to_s, redirects - 1)
      else raise Error, "GET #{url}: #{response.code}"
      end
    end

    # [fetcher] a callable taking a URL and returning its body (default
    #           HTTP_FETCHER; the specs pass their own)
    def initialize(fetcher: HTTP_FETCHER)
      @fetcher = fetcher
    end

    # Installs the runtime +name+.
    #
    # [version]    the version (default: WarpEngine::Runtime#chosen_version)
    # [components] the components, a Hash of kind to keys (default: what the
    #              platforms' bindings need, WarpEngine::Runtime#required_components,
    #              plus what the version already has)
    # [dry_run]    only report what would be fetched
    #
    # Returns a Result. Raises Error (see there) and ArgumentError for an
    # unknown runtime. Writes the files and the records.
    def install(name:, version: nil, components: nil, dry_run: false)
      runtime = WarpEngine::Runtime.find!(name)
      definition = runtime.definition
      raise Error, "#{name} is uploaded by a build, not downloaded" unless definition.download?

      version = (version || runtime.chosen_version).to_s
      spec = definition.versions[version] || raise(Error, "#{name} has no version #{version}")
      record = WarpEngine::RuntimeVersion.find_by(name: name, version: version)
      wanted = merge_components(components || runtime.required_components, record)
      files = definition.base_files(version) + component_files(definition, spec, wanted)

      directory = WarpEngine::Runtime.directory(name, version)
      root = Pathname.new(WarpEngine.config.file_container_path).join(directory)
      fetched, kept = files.uniq.partition { |file| digest_of(root.join(file)) != spec.checksums.fetch(file) }
      return Result.new(nil, name, version, fetched, kept, wanted, true) if dry_run

      fetched.each { |file| fetch(spec, file, root.join(file)) }
      record = notice!(save(record, name, version, directory, root, spec.checksums.slice(*files), wanted))
      Result.new(record, name, version, fetched, kept, wanted, false)
    end

    # Writes the runtime's licence notice into the folder of
    # +runtime_version+ (a WarpEngine::RuntimeVersion) as
    # WarpEngine::Runtime::NOTICE, when it is missing or differs, and records
    # its digest. Returns +runtime_version+; a runtime without a notice, or one
    # no longer defined, is left as it is.
    def notice!(runtime_version)
      source = runtime_version.runtime&.definition&.notice
      return runtime_version if source.nil?

      digest = Digest::SHA256.file(source).hexdigest
      target = Pathname.new(WarpEngine.config.file_container_path).join(runtime_version.path, WarpEngine::Runtime::NOTICE)
      WarpEngine::Files.atomic(target.to_s) { |temporary| FileUtils.cp(source, temporary) } unless digest_of(target) == digest
      return runtime_version if runtime_version.file_digests[WarpEngine::Runtime::NOTICE] == digest

      files = runtime_version.file_digests.merge(WarpEngine::Runtime::NOTICE => digest)
      root = target.dirname
      runtime_version.update!(files: files, size_bytes: files.keys.sum { |file| File.file?(root.join(file)) ? File.size(root.join(file)) : 0 })
      runtime_version
    end

    # Returns the files of the WarpEngine::RuntimeVersion +runtime_version+
    # that are missing or whose SHA-256 differs from the recorded one, as an
    # Array of relative paths; empty when every file is intact. Reads every
    # file.
    def verify(runtime_version)
      root = Pathname.new(WarpEngine.config.file_container_path).join(runtime_version.path)
      runtime_version.file_digests.reject { |file, digest| digest_of(root.join(file)) == digest }.keys
    end

    private

    def merge_components(wanted, record)
      merged = wanted.to_h.transform_keys(&:to_s).transform_values { |keys| Array(keys).map(&:to_s) }
      record&.runtime_components&.each do |component|
        merged[component.kind] = (merged[component.kind] || []) | [ component.key ]
      end
      merged
    end

    def component_files(definition, spec, wanted)
      wanted.flat_map do |kind, keys|
        component = definition.components[kind] || raise(Error, "#{definition.name} has no #{kind} components")
        keys.flat_map do |key|
          files = component.files(key, spec.checksums)
          raise Error, "#{definition.name} #{spec.version} has no #{kind} #{key}" if files.empty?

          files
        end
      end
    end

    def digest_of(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil

    def fetch(spec, file, target)
      body = @fetcher.call("#{spec.source}#{file}")
      digest = Digest::SHA256.hexdigest(body)
      raise Error, "#{file}: SHA-256 #{digest} differs from #{spec.checksums.fetch(file)}" unless digest == spec.checksums.fetch(file)

      FileUtils.mkdir_p(target.dirname)
      WarpEngine::Files.atomic(target.to_s) { |temporary| File.binwrite(temporary, body) }
    end

    def save(record, name, version, directory, root, digests, wanted)
      ActiveRecord::Base.transaction do
        record ||= WarpEngine::RuntimeVersion.new(name: name, version: version)
        record.update!(source: "download", path: directory, deleted_at: nil,
                       files: record.file_digests.merge(digests),
                       size_bytes: record.file_digests.merge(digests).keys.sum { |file| File.size(root.join(file)) })
        wanted.each do |kind, keys|
          keys.each { |key| record.runtime_components.find_or_create_by!(kind: kind, key: key) }
        end
        record
      end
    end
  end
end
