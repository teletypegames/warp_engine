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
      file_stats = WarpEngine::Download.where(release_id: resource.id)
                           .group(:file_path)
                           .select("file_path, COUNT(*) as dl_count, MAX(created_at) as last_dl")
                           .order("dl_count DESC")

      if file_stats.any?
        div style: "margin-bottom:8px;" do
          strong "Total downloads: "
          b file_stats.sum(&:dl_count).to_s
        end

        table_for file_stats do
          column("File") { |row| span row.file_path, style: "font-family:monospace;font-size:12px;" }
          column("Downloads") { |row| row.dl_count }
          column("Last download") { |row| row.last_dl&.strftime("%Y-%m-%d %H:%M") }
        end
      else
        para "No downloads for this release.", style: "color:#999;font-style:italic;"
      end
    end
  end
end
