ActiveAdmin.register WarpEngine::ApplicationToken, as: "Application Token" do
  actions :index, :show, :new, :create, :edit, :update, :destroy
  permit_params :name, :owner_id, :expires_at, :scopes_string, :unrestricted

  menu priority: 9, label: "🎟️ App Tokens"

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
            "application_token_owner_class nincs beállítva — token nem hozható létre.",
            class: "flash flash_error"))
        end
      end
      f.input :name
      f.input :scopes_string, label: "Scopes (comma separated)",
              hint: %(A /build/publish (és a legacy /update) végponthoz az "update", a /build/upload-hoz az "upload" scope kell.)
      f.input :unrestricted, hint: "Belső token: az owner-izoláció (enforce_software_ownership) nem vonatkozik rá."
      f.input :expires_at, hint: "Üresen hagyva sosem jár le."
    end
    f.actions
  end

  show do
    if (plain = controller.instance_variable_get(:@plain_token))
      panel "⚠️ Token — csak most látható, másold ki!" do
        pre plain, style: "font-family:monospace;font-size:14px;padding:8px;background:#fff3cd;user-select:all;"
      end
    end
    attributes_table do
      row :id
      row :name
      row("Token") { |t| code "#{t.token_prefix}… (SHA256 digest tárolva)" }
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
    # A plain token csak közvetlenül a létrehozás után létezik; a session-ön át
    # jut el az egyszeri megjelenítésig (a flash nem jó: az AA layout minden
    # flash kulcsot üzenetsávként renderel).
    def create
      create! do |success, _failure|
        success.html do
          session[:warp_engine_plain_token] = resource.plain_token
          redirect_to resource_path(resource) and return
        end
      end
    end

    def show
      @plain_token = session.delete(:warp_engine_plain_token)
      show!
    end

    # Revoke = soft delete, audit-nyommal.
    def destroy
      resource.revoke!
      redirect_to collection_path, notice: "Token revoked."
    end
  end
end
