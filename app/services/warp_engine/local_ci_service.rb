module WarpEngine
  # Sets a software up on the local git server and CI
  # (WarpEngine::Local): turns them on when they are not, gives the
  # software its repository and CI through WarpEngine::ScaffoldService#connect
  # (the seams answer with the local providers' adapters), and lets each
  # provider add its part — the git server the push address. The result is
  # what a tool needs to push: +pushUrl+, +remoteName+, +repoUrl+,
  # +ciRepositoryId+, +warnings+.
  class LocalCiService
    # The git remote name a tool adds the push address under.
    REMOTE_NAME = "wplocal".freeze

    # [providers] the WarpEngine::LocalProviderService that turns the providers on
    def initialize(providers: LocalProviderService.new)
      @providers = providers
    end

    # Queues the set-up of +software+ for +owner+ (who owns the CI token).
    # Returns the WarpEngine::LocalTask.
    def queue(software, owner)
      raise Local::Error, Local.unavailable_reason unless Local.available?

      task = LocalTask.create!(kind: "local_ci", target: software.id.to_s,
                                         result: { "ownerType" => owner.class.name, "ownerId" => owner.id })
      LocalTaskJob.perform_later(task.id)
      task
    end

    # Runs the set-up the WarpEngine::LocalTask +task+ names.
    # Returns the result Hash. Raises WarpEngine::Local::Error or
    # WarpEngine::Scm::Error when a step fails.
    def setup(task)
      software = Software.kept.find(task.target)
      owner = owner_of(task)
      scm = @providers.ensure_role(:scm, task)
      ci = @providers.ensure_role(:ci, task)
      task.step!("give #{software.name} its repository and CI")
      connected = ScaffoldService.new(scm: WarpEngine.scm, ci: WarpEngine.ci).connect(software: software, owner: owner)
      result = { remoteName: REMOTE_NAME, ciRepositoryId: connected.ci_repository&.id, warnings: connected.warnings }
      [ scm, ci ].each { |provider| provider.connect(software, task, result) }
      result
    end

    # Stops CI for +software+ (its repository stays). Returns +true+ when a
    # repository was active.
    def teardown(software)
      repository = CiRepository.active.find_by(software: software)
      return false unless repository

      CiRepositorySyncService.new(ci: WarpEngine.ci).deactivate(repository.woodpecker_repo_id)
      true
    end

    private

    def owner_of(task)
      data = task.result.to_h
      data["ownerType"].to_s.safe_constantize&.find_by(id: data["ownerId"]) or raise Local::Error, "the owner of the CI token is gone"
    end
  end
end
