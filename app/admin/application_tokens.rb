ActiveAdmin.register WarpEngine::ApplicationToken, as: "Application Token" do
  actions :index, :show, :new, :create, :edit, :update, :destroy
  permit_params :name, :owner_id, :expires_at, :scopes_string, :unrestricted

  menu parent: "WarpEngine", priority: 9, label: "🎟️ App Tokens"

  config.sort_order = "created_at_desc"
  config.batch_actions = false

  scope :all, default: true
  scope("Active")  { |scope| scope.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope("Expired") { |scope| scope.where("expires_at <= ?", Time.current) }

  index do
    id_column
    column :name
    column("Token") { |t| code "#{t.token_prefix}…", style: "font-family:monospace;" }
    column("Owner") { |t| t.owner.try(:email) || t.owner.try(:name) || "#{t.owner_type} ##{t.owner_id}" }
    column("Scopes") { |t| t.scopes_string }
    column :unrestricted
    column :expires_at
    column :last_used_at
    column :created_at
    actions
  end

  filter :name_cont, label: "Name"
  filter :token_prefix_cont, label: "Token prefix"
  filter :expires_at
  filter :last_used_at

  form do |f|
    owner_class = WarpEngine.config.application_token_owner_class&.safe_constantize
    f.inputs do
      if f.object.new_record?
        if owner_class
          f.input :owner_id, as: :select, label: owner_class.name,
                  collection: owner_class.all.map { |o| [ o.try(:email) || o.try(:name) || "##{o.id}", o.id ] },
                  include_blank: false
        else
          f.template.concat(f.template.content_tag(:li,
            "application_token_owner_class is not configured — tokens cannot be created.",
            class: "flash flash_error"))
        end
      end
      f.input :name
      f.input :scopes_string, label: "Scopes (comma separated)",
              hint: %(The "update" scope is required for /build/publish, the "upload" scope for /build/upload.)
      f.input :unrestricted, hint: "Internal token: exempt from owner isolation (enforce_software_ownership)."
      f.input :expires_at, hint: "Leave empty for a token that never expires."
    end
    f.actions
  end

  action_item :rotate, only: :show do
    if WarpEngine.woodpecker_configured?
      link_to "Rotate Token", rotate_admin_application_token_path(resource),
              method: :post, data: { confirm: "This will revoke the current token, create a new one, and push it to Woodpecker. Continue?" }
    end
  end

  member_action :rotate, method: :post do
    result = WarpEngine::CiSecretSyncService.new.rotate(resource)
    if result[:rotated]
      session[:warp_engine_plain_token] = result[:new_token].plain_token
      redirect_to resource_path(result[:new_token]),
        notice: "Token rotated and synced to #{result.dig(:sync_result, :synced)&.size || 0} repo(s)"
    else
      redirect_to resource_path(resource),
        alert: "Rotation failed: #{result[:reason]}"
    end
  end

  show do
    if (plain = controller.instance_variable_get(:@plain_token))
      panel "⚠️ Token — shown only once, copy it now!" do
        pre plain, style: "font-family:monospace;font-size:14px;padding:8px;background:#fff3cd;user-select:all;"
      end
    end
    attributes_table do
      row :id
      row :name
      row("Token") { |t| code "#{t.token_prefix}… (SHA256 digest stored)" }
      row("Owner") { |t| "#{t.owner_type} ##{t.owner_id} — #{t.owner.try(:email) || t.owner.try(:name)}" }
      row("Scopes") { |t| t.scopes_string }
      row :unrestricted
      row :expires_at
      row :last_used_at
      row :created_at
      row :updated_at
    end
  end

  controller do
    # The plain token only exists right after creation; it travels via the
    # session to its one-time display (flash is unsuitable: the AA layout
    # renders every flash key as a message bar).
    def create
      create! do |success, _failure|
        success.html do
          session[:warp_engine_plain_token] = resource.plain_token

          if WarpEngine.woodpecker_configured?
            service = WarpEngine::CiSecretSyncService.new
            repos = service.repos_for_token(resource)
            if repos.any?
              result = service.provision(resource.plain_token, repos: repos)
              flash[:notice] = "Token created and synced to #{result[:synced].size} repo(s)."
              if result[:failed].any?
                flash[:alert] = "Failed to sync to #{result[:failed].size} repo(s)."
              end
            end
          end

          redirect_to resource_path(resource) and return
        end
      end
    end

    def show
      @plain_token = session.delete(:warp_engine_plain_token)
      show!
    end

    def destroy
      if WarpEngine.woodpecker_configured?
        WarpEngine::CiSecretSyncService.new.deprovision(resource)
      end
      resource.revoke!
      redirect_to collection_path, notice: "Token revoked and Woodpecker secrets cleaned up."
    end
  end
end
