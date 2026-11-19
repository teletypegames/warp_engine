module WarpEngine
  # Starts a new software in one step, the way a developer tool asks for it:
  # an empty repository on the forge (WarpEngine.forge), CI for it
  # (WarpEngine.ci), a draft WarpEngine::Software owned by the caller with a
  # +Repository+ link, an ApplicationToken with the +update+ and +upload+
  # scopes written into the pipeline's secret, and the
  # <tt>warp_engine.scaffold</tt> notification for the host's own
  # integrations. The project files are the tool's business: it pushes them
  # into the repository.
  class ScaffoldService
    # The name of the notification sent after a scaffold; its payload holds
    # +software+, +repo+ (the WarpEngine::Forge::Repo) and +pipeline+.
    NOTIFICATION = "warp_engine.scaffold".freeze

    # The form of a new software name: lower-case letters, digits and dashes,
    # as a repository name and an upload name take it.
    NAME_FORMAT = /\A[a-z0-9][a-z0-9-]{0,62}\z/

    # The status a new software starts with.
    STATUS = "development".freeze

    # Raised when the scaffold cannot be done: an invalid or taken name, an
    # unknown platform, no forge.
    class Error < WarpEngine::Error; end

    # What a scaffold made: the +software+, the forge +repo+, the +pipeline+
    # (or +nil+ without CI) and +warnings+, the steps that did not go through
    # but left the rest usable.
    Result = ::Data.define(:software, :repo, :pipeline, :warnings)

    # [forge] the forge adapter (default: WarpEngine.forge)
    # [ci]    the CI adapter (default: WarpEngine.ci)
    def initialize(forge: WarpEngine.forge, ci: WarpEngine.ci)
      @forge = forge
      @ci = ci
    end

    # Scaffolds the software +name+.
    #
    # [name]        the software and repository name (NAME_FORMAT)
    # [title]       the catalog title
    # [platform]    a WarpEngine::Platform name
    # [owner]       the record owning the software and the CI token
    # [category]    a category key, or +nil+
    # [description] the repository and catalog description, or +nil+
    #
    # Returns a Result. Raises Error before anything is created when the name,
    # the platform or the forge does not do; raises WarpEngine::Forge::Error
    # when the forge refuses the repository.
    def scaffold(name:, title:, platform:, owner:, category: nil, description: nil)
      check!(name, title, platform)
      repo = @forge.create_repo(name: name, description: description.presence || title)
      warnings = []

      software = WarpEngine::Software.create!(name: name, title: title, platform: platform, status: STATUS,
                                              category: category.presence, desc: description.presence, owner: owner)
      WarpEngine::ExternalLink.create!(software: software, label: Publish::Recorder::REPO_LABEL, url: repo.html_url)

      pipeline = connect_ci(repo, software, owner, warnings)
      ActiveSupport::Notifications.instrument(NOTIFICATION, software: software, repo: repo, pipeline: pipeline)
      Result.new(software: software, repo: repo, pipeline: pipeline, warnings: warnings)
    end

    # Gives the existing +software+ its repository and CI, the way #scaffold
    # does for a new one: the forge's repository of its name (made when there
    # is none), the +Repository+ link, CI for it and, the first time, a CI
    # token for +owner+ in the pipeline's secret. Running it again changes
    # nothing that is there.
    #
    # Returns a Result. Raises Error without a forge and WarpEngine::Forge::Error
    # when the forge refuses.
    def connect(software:, owner:)
      raise Error, "no forge is configured" unless @forge.configured?

      repo = @forge.find_repo(software.name) || @forge.create_repo(name: software.name, description: software.desc.presence || software.title)
      unless WarpEngine::ExternalLink.kept.exists?(software: software, label: Publish::Recorder::REPO_LABEL)
        WarpEngine::ExternalLink.create!(software: software, label: Publish::Recorder::REPO_LABEL, url: repo.html_url)
      end
      warnings = []
      known = WarpEngine::Pipeline.kept.find_by(software: software, active: true, repo_owner: repo.owner, repo_name: repo.name)
      pipeline = known || connect_ci(repo, software, owner, warnings)
      Result.new(software: software, repo: repo, pipeline: pipeline, warnings: warnings)
    end

    private

    def check!(name, title, platform)
      raise Error, "the name may have lower-case letters, digits and dashes" unless name.to_s.match?(NAME_FORMAT)
      raise Error, "the title is missing" if title.blank?
      raise Error, "#{platform} is not a platform" unless WarpEngine::Platform.exists?(platform)
      raise Error, "#{name} is taken in the catalog" if WarpEngine::Software.exists?(name: name)
      raise Error, "no forge is configured" unless @forge.configured?
    end

    def connect_ci(repo, software, owner, warnings)
      unless @ci.configured?
        warnings << "no CI is configured: the repository builds nothing yet"
        return nil
      end

      pipeline = WarpEngine::PipelineSyncService.new(ci: @ci).activate_forge(repo.id)
      pipeline.update!(software: software, platform: software.platform)
      provision_token(pipeline, software, owner, warnings)
      pipeline
    rescue CI::Error => e
      warnings << "CI was not enabled: #{e.message}"
      nil
    end

    def provision_token(pipeline, software, owner, warnings)
      token = WarpEngine::ApplicationToken.create!(
        name: "#{software.name} CI", owner_type: owner.class.name, owner_id: owner.id,
        scopes: [ WarpEngine::ApplicationToken::UPDATE_SCOPE, WarpEngine::ApplicationToken::UPLOAD_SCOPE ]
      )
      failed = WarpEngine::SecretSyncService.new(ci: @ci).provision(token.plain_token, pipelines: [ pipeline ])[:failed]
      failed.each { |failure| warnings << "the CI secret was not set: #{failure[:error]}" }
    end
  end
end
