namespace :warp_engine do
  namespace :runtimes do
    dry_run = -> { ENV["DRY_RUN"] == "1" }
    platforms = -> { ENV["PLATFORMS"].to_s.split(",").map(&:strip).presence }
    report = lambda do |title, result, dry|
      puts "#{title}#{' (dry run)' if dry}: #{result.count}"
      result.lines.each { |line| puts "  #{line}" }
    end

    desc "List the runtimes, their installed versions and the platforms bound to them"
    task list: :environment do
      WarpEngine::Runtime.all.each do |runtime|
        current = runtime.current_version
        puts "#{runtime.name} (#{runtime.label}, #{runtime.download? ? 'downloaded' : 'uploaded'}) " \
             "chosen: #{runtime.chosen_version || '-'} · platforms: #{runtime.platforms.join(', ').presence || '-'}"
        WarpEngine::RuntimeVersion.kept.where(name: runtime.name).includes(:runtime_components).order(:created_at).each do |version|
          components = version.runtime_components.map { |component| "#{component.kind} #{component.key}" }
          puts "  #{version.version}#{' *' if version == current} " \
               "#{ActiveSupport::NumberHelper.number_to_human_size(version.size_bytes)} · #{version.releases.count} releases" \
               "#{" · #{components.join(', ')}" if components.any?}"
        end
      end
    end

    desc "Install the downloaded runtimes and the components the platforms need " \
         "(NAME=, VERSION=, COMPONENTS=core:vice_x64,core:puae; DRY_RUN=1 only lists)"
    task install: :environment do
      names = ENV["NAME"].present? ? [ ENV["NAME"] ] : WarpEngine::Runtime.all.select(&:download?).map(&:name)
      components = ENV["COMPONENTS"].to_s.split(",").each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |pair, all|
        kind, key = pair.split(":", 2)
        all[kind.strip] << key.strip if key.present?
      end
      service = WarpEngine::RuntimeInstallService.new
      names.each do |name|
        runtime = WarpEngine::Runtime.find!(name)
        wanted = components.presence && runtime.required_components.merge(components) { |_, a, b| a | b }
        result = service.install(name: name, version: ENV["VERSION"].presence, components: wanted, dry_run: dry_run.call)
        puts "#{name} #{result.version}#{' (dry run)' if result.dry_run}: #{result.fetched.size} to fetch, #{result.kept.size} in place"
        result.fetched.each { |file| puts "  + #{file}" }
      end
      next if dry_run.call || ENV["NAME"].present?

      WarpEngine::RuntimeVersion.kept.each { |version| service.notice!(version) }
    end

    desc "Check every installed runtime file against its recorded SHA-256 (fails when one differs)"
    task verify: :environment do
      service = WarpEngine::RuntimeInstallService.new
      broken = WarpEngine::RuntimeVersion.kept.flat_map do |version|
        service.verify(version).map { |file| "#{version.path}/#{file}" }
      end
      broken.each { |file| puts "damaged or missing: #{file}" }
      abort "#{broken.size} runtime file(s) damaged or missing." if broken.any?
      puts "Every runtime file is intact."
    end

    desc "Move the releases of a runtime version to another (NAME=, FROM=, TO=; DRY_RUN=1 only lists)"
    task rebind: :environment do
      result = WarpEngine::RuntimeMaintenanceService.new.rebind(name: ENV.fetch("NAME"), from: ENV.fetch("FROM"),
                                                                 to: ENV.fetch("TO"), dry_run: dry_run.call)
      report.call("Releases moved", result, dry_run.call)
    end

    desc "Bind the releases that play from an html folder to the runtime version the folder holds; UNPLAYED=1 " \
         "binds the ones without an html folder to the current version (PLATFORMS=c64,plus4; EXCLUDE=dosinst; DRY_RUN=1 only lists)"
    task migrate: :environment do
      result = WarpEngine::RuntimeMaintenanceService.new.migrate(dry_run: dry_run.call, platforms: platforms.call,
                                                                  unplayed: ENV["UNPLAYED"] == "1",
                                                                  exclude: ENV["EXCLUDE"].to_s.split(",").map(&:strip))
      report.call("Releases bound", result, dry_run.call)
    end

    desc "Remove the html folders of the releases that play in a runtime (PLATFORMS=; DRY_RUN=1 only lists)"
    task prune_html: :environment do
      result = WarpEngine::RuntimeMaintenanceService.new.prune_html(dry_run: dry_run.call, platforms: platforms.call)
      report.call("html folders removed", result, dry_run.call)
    end

    desc "Remove the runtime versions no release uses and that are not current (DRY_RUN=1 only lists)"
    task gc: :environment do
      result = WarpEngine::RuntimeMaintenanceService.new.gc(dry_run: dry_run.call)
      report.call("Runtime versions removed", result, dry_run.call)
    end
  end
end
