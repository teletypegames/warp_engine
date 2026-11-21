require "open3"

module WarpEngine
  # Checks whether the +source+ link of a software can be read without a
  # sign-in: <tt>git ls-remote</tt> with every credential helper and prompt
  # turned off, so a private repository answers as private. The result goes
  # onto the WarpEngine::ExternalLink (+public+, +verified_at+,
  # +verify_error+); a fork is only offered for a public source.
  class SourceVerifyService
    # The environment of the git call: no terminal prompt, no askpass, an ssh
    # that never asks.
    GIT_ENV = {
      "GIT_TERMINAL_PROMPT" => "0",
      "GIT_ASKPASS"         => "/bin/echo",
      "SSH_ASKPASS"         => "/bin/echo",
      "GIT_SSH_COMMAND"     => "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "HOME"                => "/nonexistent"
    }.freeze

    # A check of one URL: whether it answered (+public+) and the +error+ when not.
    Result = ::Data.define(:public, :error)

    # [runner]  callable taking the command Array and the timeout, returning
    #           <tt>[output, success]</tt> (default: runs git)
    # [timeout] seconds the check may take (default WarpEngine::Forks::Configuration#timeout)
    def initialize(runner: nil, timeout: WarpEngine::Forks.config.timeout)
      @runner = runner || method(:run_git)
      @timeout = timeout
    end

    # Checks the source link +link+ and saves the result on it without
    # touching its timestamps' meaning for the URL (the URL and ref stay).
    # A link that is not a +source+ is left alone. Returns the Result, or
    # +nil+ for a non-source link.
    def verify(link)
      return nil unless link&.source?

      result = check(link.url)
      link.update_columns(public: result.public, verified_at: Time.current, verify_error: result.error&.truncate(512))
      result
    end

    # Checks +url+ without saving anything. Returns a Result.
    def check(url)
      output, success = @runner.call([ "git", "-c", "credential.helper=", "ls-remote", "--heads", "--", url.to_s ], @timeout)
      success ? Result.new(public: true, error: nil) : Result.new(public: false, error: output.to_s.strip.lines.last.to_s.strip.presence || "git ls-remote failed")
    rescue Errno::ENOENT
      Result.new(public: nil, error: "git is not installed on the engine")
    end

    # Checks every source that was never checked, and the ones checked longer
    # ago than +older_than+. Returns how many were checked.
    def verify_due(older_than: WarpEngine::Forks.config.recheck_days.days)
      links = WarpEngine::ExternalLink.kept.sources.where(verified_at: nil)
                                       .or(WarpEngine::ExternalLink.kept.sources.where(verified_at: ...older_than.ago))
      links.find_each.count { |link| verify(link) }
    end

    private

    def run_git(command, timeout)
      Open3.popen2e(GIT_ENV, *command, unsetenv_others: false) do |stdin, out, waiter|
        stdin.close
        reader = Thread.new { out.read }
        unless waiter.join(timeout)
          Process.kill("KILL", waiter.pid)
          return [ "timed out after #{timeout} seconds", false ]
        end
        [ reader.value, waiter.value.success? ]
      end
    end
  end
end
