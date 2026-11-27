namespace :warp_engine do
  namespace :local do
    quiet = -> { ActiveRecord::Base.logger = nil }

    run_task = lambda do |kind, target|
      quiet.call
      abort WarpEngine::Local.unavailable_reason unless WarpEngine::Local.available?
      abort "No local provider #{target.inspect} (#{WarpEngine::Local::Providers.classes.map(&:key).join(', ')})" if WarpEngine::Local::Providers.find(target).nil?

      local_task = WarpEngine::LocalTask.create!(kind: kind, target: target)
      worker = Thread.new { WarpEngine::LocalProviderService.new.run(local_task) }
      shown = 0
      loop do
        finished = !worker.alive?
        steps = Array(local_task.reload.steps)
        steps.drop(shown).each { |step| puts "  #{step['text']}" }
        shown = steps.size
        break if finished

        sleep 1
      end
      worker.join
      abort "#{target}: #{local_task.reload.error}" if local_task.state == "failed"
    end

    desc "List the local providers (git server, CI) and their state"
    task status: :environment do
      quiet.call
      WarpEngine::LocalProviderService.new.list.each do |line|
        puts format("%-12s %-8s %-12s %s", line.key, line.role, line.state, line.message)
      end
    end

    desc "Start a local provider and what it needs (gitea, woodpecker), and set it up; waits and prints the steps"
    task :enable, %i[key] => :environment do |_task, args|
      run_task.call("enable", args[:key].to_s)
    end

    desc "Stop a local provider and what needs it; the data stays"
    task :disable, %i[key] => :environment do |_task, args|
      run_task.call("disable", args[:key].to_s)
    end

    desc "Remove a local provider's containers (and what needs it); PURGE=1 removes its data and sign-ins too"
    task :remove, %i[key] => :environment do |_task, args|
      run_task.call(ENV["PURGE"] == "1" ? "purge" : "remove", args[:key].to_s)
    end

    desc "Print a local provider's generated sign-in as KEY=value lines (URL, USER, PASSWORD)"
    task :credentials, %i[key] => :environment do |_task, args|
      quiet.call
      record = WarpEngine::LocalProvider.find_by(key: args[:key].to_s)
      abort "#{args[:key]} was never started" if record.nil?

      record.provider.credentials.each { |key, value| puts "#{key.to_s.upcase}=#{value}" }
    end
  end
end
