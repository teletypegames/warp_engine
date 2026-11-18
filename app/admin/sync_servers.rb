ActiveAdmin.register WarpEngine::SyncServer, as: "Sync Server" do
  actions :index, :show, :new, :create, :edit, :update, :destroy
  permit_params :label, :host, :secret, :active

  menu parent: "WarpEngine", priority: 11, label: "Sync Servers"

  config.sort_order = "label_asc"
  config.batch_actions = false

  scope :all, default: true
  scope("Active")   { |scope| scope.where(active: true) }
  scope("Inactive") { |scope| scope.where(active: false) }

  index do
    id_column
    column :label
    column(:host) { |server| code server.base_url }
    column("Token") { |server| code "#{server.secret_prefix}…" }
    column(:active) { |server| status_tag(server.active ? "active" : "inactive", class: server.active ? "yes" : "no") }
    column :last_synced_at
    column(:last_error) { |server| server.last_error.to_s.truncate(80) }
    actions
  end

  filter :label_cont, label: "Label"
  filter :host_cont, label: "Host"
  filter :active
  filter :last_synced_at

  form do |f|
    unless WarpEngine::Sync.enabled?
      f.template.concat(f.template.content_tag(:li, "Sync is off: set enabled in the sync block of the initializer to push releases.",
                                               class: "flash flash_notice"))
    end
    f.inputs do
      f.input :label
      f.input :host, hint: "The other engine's base URL with its mount, e.g. https://games.example.org/warp"
      f.input :secret, as: :password, required: f.object.new_record?,
                       hint: "A token the other engine issued with the sync scope. Leave empty to keep the stored one."
      f.input :active
    end
    f.actions
  end

  action_item :check, only: :show do
    link_to "Check connection", check_admin_sync_server_path(resource), method: :post
  end

  action_item :push_latest, only: :show do
    if WarpEngine::Sync.enabled? && resource.active
      link_to "Push latest releases", push_admin_sync_server_path(resource), method: :post,
              data: { confirm: "Queue a push of the newest allowed release of every software to #{resource.label}?" }
    end
  end

  member_action :check, method: :post do
    result = WarpEngine::SyncService.new.check(resource)
    version = result.version ? " (WarpEngine #{result.version})" : ""
    if result.ok
      redirect_to resource_path(resource), notice: "#{resource.label}: #{result.message}#{version}."
    else
      redirect_to resource_path(resource), alert: "#{resource.label}: #{result.message}#{version}."
    end
  end

  member_action :push, method: :post do
    WarpEngine::SyncBackfillJob.perform_later(resource.id)
    redirect_to resource_path(resource), notice: "The pushes to #{resource.label} are being queued."
  end

  show do
    attributes_table do
      row :id
      row :label
      row(:host) { |server| code server.base_url }
      row("Token") { |server| code "#{server.secret_prefix}… (stored encrypted)" }
      row :active
      row :last_synced_at
      row :last_error
      row :created_at
      row :updated_at
    end

    if WarpEngine::Sync.config.events?
      panel "Recent events" do
        events = resource.sync_events.recent.limit(25)
        if events.any?
          table_for events do
            column("When", &:created_at)
            column("Software", &:software_name)
            column("Version", &:version)
            column("Status") { |event| status_tag event.status, class: event.succeeded? ? "yes" : (event.failed? ? "no" : nil) }
            column("Step", &:step)
            column("HTTP", &:http_status)
            column("Message") { |event| event.message.to_s.truncate(120) }
          end
        else
          para "No events yet", class: "we-muted"
        end
      end
    end
  end

  controller do
    def scoped_collection
      super.kept
    end

    def destroy
      resource.soft_delete!
      redirect_to collection_path, notice: "Sync server deleted."
    end
  end
end
