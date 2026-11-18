require "digest"
require "zip"

module WarpEngine
  # Pushes one release to one WarpEngine::SyncServer the way a CI would: every
  # file the CI uploaded for it (the upload names of the platform's kinds the
  # sync filters let go, and <tt>name-version.metadata.json</tt> on a JSON
  # platform) to <tt>POST /build/upload</tt>, then <tt>POST /build/publish</tt>.
  # A kind served unpacked whose zip is gone is zipped again from its folder.
  # The push is logged on its WarpEngine::SyncEvent and the server's
  # +last_synced_at+ / +last_error+.
  class SyncPushService
    # The outcome of #push: the +status+ (a WarpEngine::SyncEvent status) and
    # the +message+, +nil+ when it went through.
    Result = ::Data.define(:status, :message)

    # [config] the WarpEngine::Sync::Configuration, by default WarpEngine::Sync.config
    def initialize(config: Sync.config)
      @config = config
      @filter = Sync::Filter.new(config)
    end

    # Pushes +release+ to +server+, logging on +event+ (a queued
    # WarpEngine::SyncEvent, or +nil+ to start one) as attempt +attempt+,
    # through +filter+ (a WarpEngine::Sync::Filter; by default the configured
    # one), which also chooses the files. With +skip_existing+ it first asks
    # the server (WarpEngine::Sync::Client#builds) and sends nothing when it
    # has the version with every kind this push would bring; when that
    # question goes unanswered, the push goes ahead.
    #
    # Returns a Result: +skipped+ when sync is off, the server inactive, the
    # filters hold the release back, it has no files, the server has it
    # already (with +skip_existing+), or the other side has a newer version
    # (409); +failed+ when the other side refuses an upload or
    # the publish; +succeeded+ otherwise. Raises
    # WarpEngine::Sync::ConnectionError (after logging it) when the server
    # does not answer, so the job tries again.
    def push(release, server, event: nil, attempt: 1, filter: nil, skip_existing: false)
      @filter = filter if filter
      @skip_existing = skip_existing
      event ||= SyncEvent.log(direction: "outbound", status: "queued", sync_server: server, **SyncEvent.release_attributes(release))
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @files_count = 0
      @bytes = 0
      @step = nil

      reason = skip_reason(release, server)
      return finish(event, server, status: "skipped", message: reason) if reason

      event&.update!(status: "running", attempt: attempt)
      run(release, server, event)
    rescue Sync::ConnectionError => e
      finish(event, server, status: "failed", message: e.message)
      raise
    end

    private

    def skip_reason(release, server)
      return "sync is not enabled" unless @config.enabled?
      return "the server is inactive or deleted" unless server.active && server.deleted_at.nil?
      return "the secret does not decrypt; enter it again" if server.secret.nil?

      @filter.reason(release)
    end

    def run(release, server, event)
      software = release.software
      client = server.client
      if @skip_existing && (present = present_reason(client, software, release))
        return finish(event, server, status: "skipped", message: present)
      end

      with_files(release, software) do |paths|
        return finish(event, server, status: "skipped", message: "no uploaded file of the release is left") if paths.empty?

        paths.each do |path|
          @step = "upload:#{File.basename(path)}"
          response = client.upload(name: software.name, version: release.version, path: path,
                                   sha256: Digest::SHA256.file(path).hexdigest)
          return finish(event, server, status: "failed", response: response) unless response.success?

          @files_count += 1
          @bytes += File.size(path)
        end
      end

      @step = "publish"
      response = client.publish(name: software.name, platform: software.platform, version: release.version,
                                commit: release.try(:commit_sha))
      return finish(event, server, status: "succeeded", response: response) if response.success?
      return finish(event, server, status: "skipped", response: response) if response.status == 409

      finish(event, server, status: "failed", response: response)
    end

    def present_reason(client, software, release)
      @step = "check"
      response = client.builds(software.name)
      return nil unless response.success?

      actual = Array(response.body.dig("releases", release.version, "actual")).map(&:to_s)
      return nil unless response.body.fetch("releases", {}).key?(release.version)

      missing = kinds_to_send(release, software) - actual
      return nil if missing.any?

      "already on the server (#{actual.sort.join(', ').presence || 'no assets'})"
    rescue Sync::ConnectionError
      nil
    end

    def kinds_to_send(release, software)
      platform = WarpEngine::Platform.find!(software.platform)
      upload = Publish::Upload.new(name: software.name, version: release.version,
                                   root: WarpEngine::ReleaseLayout.absolute_directory(software.name, release.version))
      @filter.kind_specs(platform).select do |spec|
        File.file?(upload.path(spec.upload_name(upload.versioned))) ||
          (spec.kind.unpacked? && File.directory?(upload.path(spec.asset_name(upload.versioned))))
      end.map(&:name)
    end

    def with_files(release, software)
      platform = WarpEngine::Platform.find!(software.platform)
      upload = Publish::Upload.new(name: software.name, version: release.version,
                                   root: WarpEngine::ReleaseLayout.absolute_directory(software.name, release.version))
      Dir.mktmpdir("warp-engine-sync") do |tmp|
        paths = @filter.kind_specs(platform).filter_map { |spec| file_of(spec, upload, tmp) }
        metadata = upload.path("#{upload.versioned}.metadata.json")
        paths << metadata if %w[json].include?(platform.definition.metadata.to_s) && File.file?(metadata)
        yield paths.uniq
      end
    end

    def file_of(spec, upload, tmp)
      path = upload.path(spec.upload_name(upload.versioned))
      return path if File.file?(path)
      return nil unless spec.kind.unpacked?

      folder = upload.path(spec.asset_name(upload.versioned))
      return nil unless File.directory?(folder)

      zip_folder(folder, File.join(tmp, spec.upload_name(upload.versioned)))
    end

    def zip_folder(folder, target)
      Zip::File.open(target, Zip::File::CREATE) do |zip|
        Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).sort.each do |entry|
          next if entry.end_with?("/.", "/..") || entry == "." || entry == ".."

          source = File.join(folder, entry)
          File.directory?(source) ? zip.mkdir(entry) : zip.add(entry, source)
        end
      end
      target
    end

    def finish(event, server, status:, response: nil, message: nil)
      text = message || (response && !response.success? ? response.message : nil)
      event&.update!(status: status, step: @step, http_status: response&.status, message: text,
                     files_count: @files_count, bytes: @bytes,
                     duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started) * 1000).round)
      server.synced! if status == "succeeded"
      server.failed!("#{@step}: #{text}") if status == "failed"
      Result.new(status: status, message: text)
    end
  end
end
