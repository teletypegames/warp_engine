ActiveAdmin.register WarpEngine::Release, as: "Release" do
  actions :index, :show

  menu false

  belongs_to :software, optional: true

  index do
    selectable_column
    id_column
    column(:software) { |r| link_to r.software.title, admin_software_path(r.software) }
    column :version
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
        para "No assets for this release.", style: "color:#999;font-style:italic;"
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
        para "No downloads for this release.", style: "color:#999;font-style:italic;"
      end
    end
  end
end
