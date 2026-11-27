module WarpEngine
  # Starts a new software in one step, the way a developer tool asks for it:
  # an empty repository on the SCM (WarpEngine.scm), CI for it
  # (WarpEngine.ci), a draft WarpEngine::Software owned by the caller with a
  # +Repository+ link, an ApplicationToken with the +update+ and +upload+
  # scopes written into the repository's secret, and the
  # <tt>warp_engine.scaffold</tt> notification for the host's own
  # integrations. The project files are the tool's business: it pushes them
  # into the repository.
  class ScaffoldService
    # The name of the notification sent after a scaffold; its payload holds
    # +software+, +repo+ (the WarpEngine::Scm::Repo) and +ci_repository+.
    NOTIFICATION = "warp_engine.scaffold".freeze

    # The form of a new software name: lower-case letters, digits and dashes,
    # as a repository name and an upload name take it.
    NAME_FORMAT = /\A[a-z0-9][a-z0-9-]{0,62}\z/

    # The status a new software starts with.
    STATUS = "development".freeze

    # Raised when the scaffold cannot be done: an invalid or taken name, an
    # unknown platform, no SCM.
    class Error < WarpEngine::Error; end

    # What a scaffold made: the +software+, the SCM +repo+, the +ci_repository+
    # (or +nil+ without CI) and +warnings+, the steps that did not go through
    # but left the rest usable.
    Result = ::Data.define(:software, :repo, :ci_repository, :warnings)

    # [scm] the SCM adapter (default: WarpEngine.scm)
    # [ci]    the CI adapter (default: WarpEngine.ci)
    def initialize(scm: WarpEngine.scm, ci: WarpEngine.ci)
      @scm = scm
      @ci = ci
    end

    # Scaffolds the software +name+.
    #
    # [name]        the software and repository name (NAME_FORMAT)
    # [title]       the catalog title
    # [platform]    a WarpEngine::Platform name
    # [app]         the platform variant (+cli+, +gui+), or +nil+ for the
    #               default one
    # [owner]       the record owning the software and the CI token
    # [category]    a category key, or +nil+
    # [description] the repository and catalog description, or +nil+
    # [fork_of]     for a fork, its parent: a Hash with +engine+, +name+ and
    #               optional +version+ and +repo+ (WarpEngine::Forks), or +nil+
    # [license]     the license, or +nil+
    #
    # The repository becomes the software's WarpEngine::SoftwareSource. Returns a Result. Raises Error before anything is created when the name,
    # the platform or the SCM does not do; raises WarpEngine::Scm::Error
    # when the SCM refuses the repository.
    def scaffold(name:, title:, platform:, owner:, app: nil, category: nil, description: nil, fork_of: nil, license: nil)
      check!(name, title, platform, app)
      repo = @scm.create_repo(name: name, description: description.presence || title)
      warnings = []

      software = WarpEngine::Software.create!(name: name, title: title, platform: platform, app: app.presence, status: STATUS,
                                              category: category.presence, desc: description.presence, owner: owner,
                                              license: license.presence, **fork_attributes(fork_of))
      WarpEngine::SoftwareSource.create!(software: software, url: source_url(repo))

      repository = connect_ci(repo, software, owner, warnings)
      ActiveSupport::Notifications.instrument(NOTIFICATION, software: software, repo: repo, ci_repository: repository)
      Result.new(software: software, repo: repo, ci_repository: repository, warnings: warnings)
    end

    # Gives the existing +software+ its repository and CI, the way #scaffold
    # does for a new one: the SCM's repository of its name (made when there
    # is none), the software's source, CI for it and, the first time, a CI
    # token for +owner+ in the repository's secret. Running it again changes
    # nothing that is there.
    #
    # Returns a Result. Raises Error without an SCM and WarpEngine::Scm::Error
    # when the SCM refuses.
    def connect(software:, owner:)
      raise Error, "no SCM is configured" unless @scm.configured?

      repo = @scm.find_repo(software.name) || @scm.create_repo(name: software.name, description: software.desc.presence || software.title)
      WarpEngine::SoftwareSource.create!(software: software, url: source_url(repo)) unless WarpEngine::SoftwareSource.kept.exists?(software: software)
      warnings = []
      known = WarpEngine::CiRepository.kept.find_by(software: software, active: true, repo_owner: repo.owner, repo_name: repo.name)
      repository = known || connect_ci(repo, software, owner, warnings)
      Result.new(software: software, repo: repo, ci_repository: repository, warnings: warnings)
    end

    private

    def source_url(repo) = repo.clone_url.presence || repo.html_url

    def fork_attributes(fork_of)
      return {} if fork_of.blank?

      parent = (fork_of.respond_to?(:to_unsafe_h) ? fork_of.to_unsafe_h : fork_of.to_h).symbolize_keys
      { fork_of_engine: parent[:engine], fork_of_name: parent[:name], fork_of_version: parent[:version], fork_of_repo: parent[:repo] }
    end

    def check!(name, title, platform, app)
      raise Error, "the name may have lower-case letters, digits and dashes" unless name.to_s.match?(NAME_FORMAT)
      raise Error, "the title is missing" if title.blank?
      raise Error, "#{platform} is not a platform" unless WarpEngine::Platform.exists?(platform)
      raise Error, "#{platform} has no app #{app}" unless WarpEngine::Platform.find(platform, app: app)
      raise Error, "#{name} is taken in the catalog" if WarpEngine::Software.exists?(name: name)
      raise Error, "no SCM is configured" unless @scm.configured?
    end

    def connect_ci(repo, software, owner, warnings)
      unless @ci.configured?
        warnings << "no CI is configured: the repository builds nothing yet"
        return nil
      end

      repository = WarpEngine::CiRepositorySyncService.new(ci: @ci).activate_scm(repo.id)
      repository.update!(software: software, platform: software.platform)
      provision_token(repository, software, owner, warnings)
      repository
    rescue CI::Error => e
      warnings << "CI was not enabled: #{e.message}"
      nil
    end

    def provision_token(repository, software, owner, warnings)
      token = WarpEngine::ApplicationToken.create!(
        name: "#{software.name} CI", owner_type: owner.class.name, owner_id: owner.id,
        scopes: [ WarpEngine::ApplicationToken::UPDATE_SCOPE, WarpEngine::ApplicationToken::UPLOAD_SCOPE ]
      )
      failed = WarpEngine::SecretSyncService.new(ci: @ci).provision(token.plain_token, repositories: [ repository ])[:failed]
      failed.each { |failure| warnings << "the CI secret was not set: #{failure[:error]}" }
    end
  end
end
