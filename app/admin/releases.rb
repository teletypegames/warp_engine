ActiveAdmin.register WarpEngine::Release, as: "Release" do
  actions :index, :show

  menu false

  belongs_to :software, optional: true

  index do
    selectable_column
    id_column
    column(:software) { |r| link_to r.software.title, admin_software_path(r.software) }
    column :version
    column(:origin) { |r| r.synced? ? status_tag("from #{r.sync_peer&.label || 'sync'}", class: "no") : status_tag("ci", class: "yes") }
    column(:assets) { |r| r.release_assets.map(&:kind).sort.join(", ") }
    column :created_at
    actions only: [ :show ]
  end

  filter :version

  controller do
    def scoped_collection
      super.kept
    end
  end

  show do
    attributes_table do
      row :id
      row(:software) { |r| link_to r.software.title, admin_software_path(r.software) }
      row :version
      row(:origin) do |r|
        if r.synced?
          r.sync_peer ? link_to("from #{r.sync_peer.label} (sync)", admin_sync_peer_path(r.sync_peer)) : "sync"
        else
          "ci (published here)"
        end
      end
      row("Plays in") do |r|
        if r.runtime_version
          link_to("#{r.web_binding} · #{r.runtime_version.label}", admin_runtime_path(r.runtime_version))
        else
          r.release_assets.any? { |asset| asset.kind == "html" } ? "its html folder" : "-"
        end
      end
      row :created_at
      row :updated_at
    end

    panel "Assets" do
      if resource.release_assets.any?
        table_for resource.release_assets.order(:kind) do
          column :kind
          column(:path) { |a| span a.path, style: "font-family:monospace;font-size:12px;" }
        end
      else
        para "No assets for this release.", class: "we-muted"
      end
    end

    if WarpEngine::Sync.config.events? && resource.sync_events.exists?
      panel "Sync" do
        table_for resource.sync_events.includes(:sync_peer).limit(20) do
          column("When", &:created_at)
          column("Peer") { |event| event.sync_peer ? link_to(event.sync_peer.label, admin_sync_peer_path(event.sync_peer)) : "-" }
          column("Direction", &:direction)
          column("Status") { |event| status_tag event.status, class: event.succeeded? ? "yes" : (event.failed? ? "no" : nil) }
          column("Step", &:step)
          column("Message") { |event| event.message.to_s.truncate(100) }
        end
      end
    end

    panel "Downloads by File" do
      file_stats = WarpEngine::DownloadStatsService.new.for_release(resource)

      if file_stats.any?
        div style: "margin-bottom:8px;" do
          strong "Total downloads: "
          b file_stats.sum { |row| row[:downloads] }.to_s
        end

        table_for file_stats do
          column("File") { |row| span row[:file_path], style: "font-family:monospace;font-size:12px;" }
          column("Downloads") { |row| row[:downloads] }
          column("Last download") { |row| row[:last_download_at]&.strftime("%Y-%m-%d %H:%M") }
        end
      else
        para "No downloads for this release.", class: "we-muted"
      end
    end
  end
end
