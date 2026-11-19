module WarpEngine
  # Sets a software up on the local git server and CI
  # (WarpEngine::Local): turns them on when they are not, gives the
  # software its repository and CI through WarpEngine::ScaffoldService#connect
  # (the seams answer with the local components' adapters), and lets each
  # component add its part — the git server the push address. The result is
  # what a tool needs to push: +pushUrl+, +remoteName+, +repoUrl+,
  # +pipelineId+, +warnings+.
  class LocalCiService
    # The git remote name a tool adds the push address under.
    REMOTE_NAME = "warp".freeze

    # [components] the WarpEngine::LocalComponentService that turns the components on
    def initialize(components: LocalComponentService.new)
      @components = components
    end

    # Queues the set-up of +software+ for +owner+ (who owns the CI token).
    # Returns the WarpEngine::LocalOperation.
    def queue(software, owner)
      raise Local::Error, Local.unavailable_reason unless Local.available?

      operation = LocalOperation.create!(kind: "local_ci", target: software.id.to_s,
                                         result: { "ownerType" => owner.class.name, "ownerId" => owner.id })
      LocalOperationJob.perform_later(operation.id)
      operation
    end

    # Runs the set-up the WarpEngine::LocalOperation +operation+ names.
    # Returns the result Hash. Raises WarpEngine::Local::Error or
    # WarpEngine::Forge::Error when a step fails.
    def setup(operation)
      software = Software.kept.find(operation.target)
      owner = owner_of(operation)
      forge = @components.ensure_role(:forge, operation)
      ci = @components.ensure_role(:ci, operation)
      operation.step!("give #{software.name} its repository and CI")
      connected = ScaffoldService.new(forge: WarpEngine.forge, ci: WarpEngine.ci).connect(software: software, owner: owner)
      result = { remoteName: REMOTE_NAME, pipelineId: connected.pipeline&.id, warnings: connected.warnings }
      [ forge, ci ].each { |component| component.connect(software, operation, result) }
      result
    end

    # Stops CI for +software+ (its repository stays). Returns +true+ when a
    # pipeline was active.
    def teardown(software)
      pipeline = Pipeline.active.find_by(software: software)
      return false unless pipeline

      PipelineSyncService.new(ci: WarpEngine.ci).deactivate(pipeline.woodpecker_repo_id)
      true
    end

    private

    def owner_of(operation)
      data = operation.result.to_h
      data["ownerType"].to_s.safe_constantize&.find_by(id: data["ownerId"]) or raise Local::Error, "the owner of the CI token is gone"
    end
  end
end
