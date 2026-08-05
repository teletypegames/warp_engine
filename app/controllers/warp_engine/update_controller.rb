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
    param :secret, String, required: true, desc: "Shared secret or application token (X-Update-Secret header preferred)"
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

    # A hitelesítési forrás kizárólagos: :database módban a shared secret nem
    # érvényes, :env módban a DB-tokenek nem.
    def authorized?
      token = request.headers["X-Update-Secret"].presence || params[:secret].presence
      return false if token.blank?

      case WarpEngine.config.update_secret_source
      when :database then database_token_authorized?(token)
      else env_secret_authorized?(token)
      end
    end

    def env_secret_authorized?(token)
      expected = WarpEngine.config.update_secret
      # Konfigurálatlan secret esetén az endpoint zárva marad.
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end

    def database_token_authorized?(token)
      if WarpEngine.config.application_token_owner_class.blank?
        Rails.logger.error("[UpdateController] update_secret_source=:database, de application_token_owner_class nincs beállítva — minden kérés elutasítva")
        return false
      end

      record = WarpEngine::ApplicationToken.authenticate(token, required_scope: WarpEngine::ApplicationToken::UPDATE_SCOPE)
      return false if record.nil?

      record.touch_last_used!
      true
    end
  end
end
