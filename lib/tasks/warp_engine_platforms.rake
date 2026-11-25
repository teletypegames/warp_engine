namespace :warp_engine do
  namespace :platforms do
    desc "Check that every platform agrees with its CI template, runtimes, store engines, shelves, the CI settings " \
         "and the catalog (PLATFORMS=c64,tic80 limits it; DATA=0 leaves the database alone; FORMAT=json; exits 1 on an error)"
    task check: :environment do
      names = ENV["PLATFORMS"].presence&.split(/[\s,]+/)
      report = WarpEngine::PlatformIntegrityService.new.check(names: names, data: ENV["DATA"] != "0")

      if ENV["FORMAT"] == "json"
        puts JSON.pretty_generate("ok" => report.ok?, "platforms" => report.platforms, "findings" => report.findings.map(&:to_h))
      else
        (report.platforms + report.findings.map(&:platform)).uniq.each do |platform|
          findings = report.for(platform)
          puts findings.empty? ? "ok    #{platform}" : "#{findings.any?(&:error?) ? 'FAIL' : 'warn'}  #{platform}"
          findings.each { |finding| puts "      #{finding.error? ? 'error' : 'warning'} #{finding.code}: #{finding.message}" }
        end
        puts "#{report.platforms.size} platforms, #{report.errors.size} errors, #{report.warnings.size} warnings"
      end
      exit 1 unless report.ok?
    end
  end
end
