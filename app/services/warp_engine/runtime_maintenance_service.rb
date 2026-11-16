require "digest"
require "fileutils"

module WarpEngine
  # Keeps the installed runtimes and the releases bound to them in order:
  # moves releases from one runtime version to another (#rebind), binds the
  # releases that still play from a self-contained +html+ folder to the
  # runtime version that folder holds (#migrate), removes those folders once
  # the releases play in the runtime (#prune_html), and drops the versions no
  # release uses (#gc). Every method takes +dry_run+ and reports what it does
  # as a Report.
  class RuntimeMaintenanceService
    # What a maintenance step did (or would do): +lines+ to print, one per
    # record, and +count+, the records it changed (would change).
    Report = ::Data.define(:lines, :count)

    # Moves the releases bound to the version +from+ of the runtime +name+ to
    # its version +to+, which must be installed. Returns a Report. Raises
    # ArgumentError when a version is not installed.
    def rebind(name:, from:, to:, dry_run: true)
      source = installed!(name, from)
      target = installed!(name, to)
      releases = source.releases.includes(:software).to_a
      lines = releases.map { |release| "#{release.software.name} #{release.version}: #{from} -> #{to}" }
      WarpEngine::Release.where(id: releases.map(&:id)).update_all(runtime_version_id: target.id, updated_at: Time.current) unless dry_run
      Report.new(lines, releases.size)
    end

    # Binds every release that plays from an +html+ folder but not in a
    # runtime to its platform's default binding, in the installed version of
    # that runtime whose files (base files and the binding's components) are
    # all in the folder bit for bit. A release whose folder matches no
    # installed version, or whose page would not resolve, is left alone and
    # reported. With +unplayed+ the releases that never played on the web (no
    # +html+ asset, e.g. the DOS programs) are bound too, to the runtime's
    # current version. +platforms+ limits it to those platform names, and
    # +exclude+ leaves those software names out. Returns a Report.
    def migrate(dry_run: true, platforms: nil, unplayed: false, exclude: [])
      lines = []
      count = 0
      candidates(platforms, unplayed).each do |release, binding|
        next if Array(exclude).map(&:to_s).include?(release.software.name)

        version = release.release_assets.any? { |asset| asset.kind == "html" } ? matching_version(release, binding) : current_version(binding)
        label = "#{release.software.name} #{release.version}"
        if version.nil?
          lines << "#{label}: skipped, no installed #{binding.runtime} version fits"
          next
        end

        count += 1
        lines << "#{label}: -> #{binding.key} (#{version.label})"
        next if dry_run

        release.update_columns(runtime_version_id: version.id, web_binding: binding.key, updated_at: Time.current)
        check(release, lines, label)
      end
      Report.new(lines, count)
    end

    # Soft-deletes the +html+ asset of every release that plays in a runtime
    # (its page resolves), and removes its folder and the uploaded
    # <tt>.html.zip</tt> beside it. +platforms+ limits it to those platform
    # names. Returns a Report.
    def prune_html(dry_run: true, platforms: nil)
      lines = []
      count = 0
      scope = WarpEngine::Release.kept.where.not(runtime_version_id: nil).includes(:software, :release_assets)
      scope.find_each do |release|
        next if platforms && !Array(platforms).map(&:to_s).include?(release.software&.platform)

        html = release.release_assets.find { |asset| asset.kind == "html" }
        next if html.nil? || !playable?(release)

        count += 1
        lines << "#{release.software.name} #{release.version}: remove #{html.path}"
        next if dry_run

        html.soft_delete!
        FileUtils.rm_rf(html.path.to_s)
        FileUtils.rm_f("#{html.path.to_s.chomp('/')}.html.zip")
      end
      Report.new(lines, count)
    end

    # Soft-deletes the installed runtime versions no kept release is bound to
    # and that are not the current version of their runtime, and removes
    # their files. Returns a Report.
    def gc(dry_run: true)
      current = WarpEngine::Runtime.all.filter_map { |runtime| runtime.current_version&.id }
      unused = WarpEngine::RuntimeVersion.kept.where.not(id: current).reject { |version| version.releases.exists? }
      lines = unused.map { |version| "#{version.label}: remove #{version.path} (#{ActiveSupport::NumberHelper.number_to_human_size(version.size_bytes)})" }
      unless dry_run
        unused.each do |version|
          version.soft_delete!
          FileUtils.rm_rf(File.join(WarpEngine.config.file_container_path, version.path))
        end
      end
      Report.new(lines, unused.size)
    end

    private

    def installed!(name, version)
      WarpEngine::RuntimeVersion.kept.find_by(name: name.to_s, version: version.to_s) ||
        raise(ArgumentError, "#{name} #{version} is not installed")
    end

    def current_version(binding)
      version = binding.runtime_object&.current_version
      version if version && WarpEngine::Publish::WebBinder.components_installed?(version, binding)
    end

    def candidates(platforms, unplayed)
      WarpEngine::Release.kept.where(runtime_version_id: nil).includes(:software, :release_assets).filter_map do |release|
        software = release.software
        next if software.nil? || software.deleted_at || (platforms && !Array(platforms).map(&:to_s).include?(software.platform))

        binding = WarpEngine::Platform.find(software.platform)&.web_binding
        kinds = release.release_assets.map(&:kind)
        [ release, binding ] if binding&.valid? && (unplayed || kinds.include?("html")) && kinds.include?(binding.payload)
      end
    end

    def matching_version(release, binding)
      folder = release.release_assets.find { |asset| asset.kind == "html" }.path.to_s
      return nil unless File.directory?(folder)

      present = Dir.glob(File.join(folder, "**", "*")).select { |path| File.file?(path) }.to_set { |path| Digest::SHA256.file(path).hexdigest }
      versions = WarpEngine::RuntimeVersion.kept.where(name: binding.runtime).includes(:runtime_components).order(created_at: :desc)
      versions.find do |version|
        next false unless WarpEngine::Publish::WebBinder.components_installed?(version, binding)

        needed_files(version, binding).all? { |file| present.include?(version.file_digests[file]) }
      end
    end

    def needed_files(version, binding)
      definition = binding.runtime_object.definition
      digests = version.file_digests
      files = definition.base_files(version.version) & digests.keys
      files = digests.keys if definition.upload?
      definition.params.each_value do |param|
        key = binding.params[param.name]
        next if param.component.nil? || key.blank?

        files |= definition.components.fetch(param.component).files(key, digests)
      end
      files
    end

    def playable?(release)
      WarpEngine::PlayService.new.page(name: release.software.name, version: release.version, authorize: false)
      true
    rescue WarpEngine::PlayService::NotFound
      false
    end

    def check(release, lines, label)
      return if playable?(release)

      release.update_columns(runtime_version_id: nil, web_binding: nil)
      lines << "#{label}: rolled back, its page does not resolve"
    end
  end
end
