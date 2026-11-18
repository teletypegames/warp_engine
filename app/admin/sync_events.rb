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
    column("Peer") { |event| event.sync_peer ? link_to(event.sync_peer.label, admin_sync_peer_path(event.sync_peer)) : event.token_prefix && code("#{event.token_prefix}…") }
    column("Software") { |event| event.software ? link_to(event.software_name, admin_software_path(event.software)) : event.software_name }
    column :version
    column("Status") { |event| status_tag event.status, class: event.succeeded? ? "yes" : (event.failed? ? "no" : nil) }
    column :step
    column("Code", &:http_status)
    column(:message) { |event| event.message.to_s.truncate(80) }
    actions
  end

  filter :sync_peer, as: :select, collection: -> { WarpEngine::SyncPeer.kept.order(:label).map { |peer| [ peer.label, peer.id ] } }
  filter :software, as: :select, collection: -> { WarpEngine::Software.kept.order(:name).map { |software| [ software.name, software.id ] } }
  filter :direction, as: :select, collection: WarpEngine::SyncEvent::DIRECTIONS
  filter :status, as: :select, collection: WarpEngine::SyncEvent::STATUSES
  filter :software_name_cont, label: "Software name"
  filter :created_at

  controller do
    def scoped_collection
      super.includes(:sync_peer, :software)
    end
  end
end
