ActiveAdmin.register WarpEngine::SyncEvent, as: "Sync Event" do
  actions :index, :show

  menu parent: "WarpEngine", priority: 12, label: "Sync Events", if: -> { WarpEngine::Sync.config.events? }

  config.sort_order = "created_at_desc"
  config.batch_actions = false

  scope :all, default: true
  scope("Outbound") { |scope| scope.where(direction: "outbound") }
  scope("Inbound")  { |scope| scope.where(direction: "inbound") }
  scope("Failed")   { |scope| scope.where(status: "failed") }

  index do
    id_column
    column :created_at
    column :direction
    column("Server") { |event| event.sync_server ? link_to(event.sync_server.label, admin_sync_server_path(event.sync_server)) : event.token_prefix && code("#{event.token_prefix}…") }
    column :software_name
    column :version
    column("Status") { |event| status_tag event.status, class: event.succeeded? ? "yes" : (event.failed? ? "no" : nil) }
    column :step
    column :http_status
    column(:message) { |event| event.message.to_s.truncate(80) }
    actions
  end

  filter :sync_server, as: :select, collection: -> { WarpEngine::SyncServer.kept.order(:label).map { |s| [ s.label, s.id ] } }
  filter :direction, as: :select, collection: WarpEngine::SyncEvent::DIRECTIONS
  filter :status, as: :select, collection: WarpEngine::SyncEvent::STATUSES
  filter :software_name_cont, label: "Software"
  filter :created_at

  controller do
    def scoped_collection
      super.includes(:sync_server)
    end
  end
end
