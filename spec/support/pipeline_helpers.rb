require "open3"

# Runs pieces of a rendered pipeline in a shell, with a fake curl that logs its
# calls, so a spec checks what a step does instead of how its text reads.
module PipelineHelpers
  # Returns the commands of the step (Woodpecker) or job (GitLab) +name+ of the
  # rendered pipeline +yaml+, joined into one script.
  def step_script(yaml, name)
    document = YAML.safe_load(yaml)
    step = document["steps"]&.find { |candidate| candidate["name"] == name }
    (step ? step["commands"] : document.fetch(name)["script"]).join("\n")
  end

  # Runs +script+ in a directory holding +files+ (name => content) and a
  # <tt>.version</tt> of +version+, with +env+ and a curl that logs its
  # arguments and, like the real one, fails on a missing <tt>file=@</tt>
  # upload. Returns <tt>[calls, status]</tt>: the logged curl lines and the
  # exit status.
  def run_with_fake_curl(script, files: {}, version: "1.0", env: {})
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".version"), version)
      files.each do |file, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, file)))
        File.write(File.join(dir, file), content)
      end
      bin = File.join(dir, ".bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "curl"), <<~SH)
        #!/bin/sh
        echo "$*" >> "#{dir}/.calls"
        for arg in "$@"; do
          case "$arg" in file=@*) [ -f "${arg#file=@}" ] || exit 26 ;; esac
        done
      SH
      File.chmod(0o755, File.join(bin, "curl"))
      _, status = Open3.capture2e({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" }.merge(env), "sh", "-c", script, chdir: dir)
      calls = File.exist?(File.join(dir, ".calls")) ? File.readlines(File.join(dir, ".calls"), chomp: true) : []
      [ calls, status ]
    end
  end

  # Returns the file names the upload calls of +calls+ sent.
  def uploaded_files(calls) = calls.filter_map { |call| call[/file=@(\S+)/, 1] }
end

RSpec.configure { |config| config.include PipelineHelpers }
