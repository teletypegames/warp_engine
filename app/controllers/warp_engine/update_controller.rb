module WarpEngine
  class UpdateController < ApiController
    resource_description do
      short "Software updater"
      formats [ "text" ]
    end

    rescue_from ArgumentError do |e|
      render plain: e.message, status: :bad_request
    end

    rescue_from StandardError do |e|
      Rails.logger.error("[UpdateController] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render plain: "Internal server error", status: :internal_server_error
    end

    api :GET, "/update", "Update software version in database"
    param :secret, String, required: true, desc: "Authorization secret"
    param :platform, String, required: false, desc: "Platform (tic80, love, ebitengine, c64, godot, bevy, phaser)"
    param :name, String, required: false, desc: "Software name"
    param :version, String, required: true, desc: "Version string"
    returns code: 200, desc: "Plain text 'Updated'"
    error code: 401, desc: "Invalid secret"
    error code: 400, desc: "Version not provided or invalid arguments"
    error code: 500, desc: "Internal server error"
    def update
      return render plain: "Unauthorized", status: :unauthorized unless authorized?
      return render plain: "Version not provided", status: :bad_request if params[:version].blank?

      input = WarpEngine::UpdateInputDto.new(
        platform: params[:platform],
        name:     params[:name],
        version:  params[:version]
      )

      WarpEngine::UpdateService.new.update(input)
      render plain: "Updated"
    end

    private

    def authorized?
      secret = request.headers["X-Update-Secret"].presence || params[:secret]
      expected = WarpEngine.config.update_secret
      # Konfigurálatlan secret esetén az endpoint zárva marad.
      expected.present? && secret == expected
    end
  end
end
