module WarpEngine
  module Build
    # Checks a publish without making it (WarpEngine::PublishCheckService), so
    # a developer's editor can show what the CI's publish would refuse before
    # the push.
    class ChecksController < ApiController
      resource_description do
        short "Publish checks for developer tools"
      end

      api :POST, "/build/check", "Check a publish without making it"
      param :platform, String, required: true, desc: "Platform name"
      param :metadata, Hash, required: true, desc: "The metadata a publish would read"
      param :version, String, required: false, desc: "The version the pipeline would publish"
      param :kinds, Array, required: false, desc: "The asset kinds the build would upload"
      returns code: 200, desc: %(JSON: {"ok": true|false, "problems": [{"field", "message", "level"}]})
      # <tt>POST /build/check</tt>, a JSON body.
      #
      # [platform] the platform name
      # [metadata] the metadata a publish would read
      # [version]  the version the pipeline would publish (optional)
      # [kinds]    the asset kinds the build would upload (optional)
      #
      # Renders <tt>{ "ok", "problems" }</tt>: +ok+ is +false+ when a problem is
      # an error. A bearer application token, when sent, makes the check of
      # software ownership count its owner. Writes nothing.
      def create
        metadata = params[:metadata].respond_to?(:to_unsafe_h) ? params[:metadata].to_unsafe_h : {}
        kinds = params.key?(:kinds) ? Array(params[:kinds]) : nil
        problems = WarpEngine::PublishCheckService.new.check(platform: params[:platform].to_s, metadata: metadata,
                                                             version: params[:version].presence, kinds: kinds,
                                                             owner: bearer_owner).map(&:to_h)

        render json: { ok: problems.none? { |problem| problem["level"] == "error" }, problems: problems }
      end

      private

      def bearer_owner
        token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        WarpEngine::ApplicationToken.authenticate(token)&.owner
      end
    end
  end
end
