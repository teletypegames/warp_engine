module WarpEngine
  # Creates, revokes and rotates WarpEngine::ApplicationToken records and keeps
  # the token secret of the matching CI pipelines in step (see SecretSyncService).
  class ApplicationTokenService
    # The outcome of #create: the +token+ (saved or carrying its validation
    # errors) and the +sync+ result of provisioning it to the CI, or +nil+ when
    # nothing was provisioned.
    Result = Struct.new(:token, :sync, keyword_init: true) do
      # Whether the token was saved.
      def created? = token.persisted?
    end

    # [ci] the CI adapter, by default WarpEngine.ci
    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    # Saves a new WarpEngine::ApplicationToken from +attributes+ and, when it
    # saved, provisions it to its pipelines (#provision). Returns a Result.
    def create(attributes)
      token = ApplicationToken.new(attributes)
      return Result.new(token: token, sync: nil) unless token.save

      Result.new(token: token, sync: provision(token))
    end

    # Writes the plain value of +token+ as the pipeline secret of every active
    # pipeline the token may publish for. Returns the SecretSyncService#provision
    # result, or +nil+ when the CI is not configured or there are no pipelines.
    def provision(token)
      return nil unless @ci.configured?

      service = SecretSyncService.new(ci: @ci)
      pipelines = service.pipelines_for_token(token)
      return nil if pipelines.empty?

      service.provision(token.plain_token, pipelines: pipelines)
    end

    # Removes the pipeline secrets of +token+ (when the CI is configured) and
    # soft-deletes the token.
    def revoke(token)
      SecretSyncService.new(ci: @ci).deprovision(token) if @ci.configured?
      token.revoke!
    end

    # Replaces +token+ with a new one and provisions it; see SecretSyncService#rotate.
    def rotate(token)
      SecretSyncService.new(ci: @ci).rotate(token)
    end
  end
end
