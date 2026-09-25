module WarpEngine
  class ApplicationTokenService
    Result = Struct.new(:token, :sync, keyword_init: true) do
      def created? = token.persisted?
    end

    def initialize(ci: WarpEngine.ci)
      @ci = ci
    end

    def create(attributes)
      token = ApplicationToken.new(attributes)
      return Result.new(token: token, sync: nil) unless token.save

      Result.new(token: token, sync: provision(token))
    end

    def provision(token)
      return nil unless @ci.configured?

      service = SecretSyncService.new(ci: @ci)
      pipelines = service.pipelines_for_token(token)
      return nil if pipelines.empty?

      service.provision(token.plain_token, pipelines: pipelines)
    end

    def revoke(token)
      SecretSyncService.new(ci: @ci).deprovision(token) if @ci.configured?
      token.revoke!
    end

    def rotate(token)
      SecretSyncService.new(ci: @ci).rotate(token)
    end
  end
end
