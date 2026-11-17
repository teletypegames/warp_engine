module WarpEngine
  # The release channels, read from a release's version so that the two can
  # never disagree:
  #
  # [+stable+] a plain version (<tt>1.2.0</tt>): what everyone is offered
  # [+beta+]   a pre-release (<tt>1.3.0-beta.1</tt>, <tt>1.0-alpha</tt>, <tt>2.0.0-rc.2</tt>):
  #            listed, and the latest only for a caller who asks for beta
  # [+dev+]    a development build (<tt>dev-1.2.0-feature</tt>, <tt>dev-3fb3ed8</tt>): never
  #            listed nor the latest; reachable by its own links and the Admin API
  module Channels
    # Every channel, from the widest audience to the narrowest.
    ALL = %w[stable beta dev].freeze

    # The channel of a version without a pre-release part.
    STABLE = "stable".freeze
    # The channel of a pre-release version.
    BETA = "beta".freeze
    # The channel of a development build.
    DEV = "dev".freeze

    # A version with a pre-release part: numbers, then a dash.
    PRE_RELEASE = /\A\d+(\.\d+)*-/

    module_function

    # Returns the channel of +version+: DEV for <tt>dev-</tt>, BETA for a
    # pre-release, STABLE otherwise.
    def for(version)
      text = version.to_s
      return DEV if text.start_with?("dev-")
      return BETA if text.delete_prefix("v").match?(PRE_RELEASE)

      STABLE
    end

    # Returns the channels whose releases a caller asking for +channel+ may get
    # as the latest: STABLE, or STABLE and BETA for BETA. Raises ArgumentError
    # for DEV or an unknown channel.
    def offered(channel)
      case channel.to_s
      when STABLE then [ STABLE ]
      when BETA then [ STABLE, BETA ]
      else raise ArgumentError, "no release is offered on the #{channel} channel"
      end
    end

    # Returns the branch a development build was made of: what follows
    # <tt>dev-</tt> and the version numbers (<tt>dev-1.2.0-feature-x</tt> →
    # <tt>feature-x</tt>; the CI writes the branch with its slashes as dashes),
    # or +nil+ for a build named after its commit (<tt>dev-3fb3ed8</tt>) or a
    # version that is no development build.
    def branch_of(version)
      version.to_s[/\Adev-\d+(?:\.\d+)*-(.+)\z/, 1]
    end
  end
end
