ActiveAdmin.register WarpEngine::Download, as: "Download" do
  actions :index, :show

  menu parent: "🌀 WarpEngine", priority: 7, label: "📊 Download Stats"

  scope :all, default: true
  scope("Today")         { |scope| scope.where("downloads.created_at >= ?", Date.current.beginning_of_day) }
  scope("This week")     { |scope| scope.where("downloads.created_at >= ?", 1.week.ago) }
  scope("This month")    { |scope| scope.where("downloads.created_at >= ?", 1.month.ago) }
  scope("With release")    { |scope| scope.where.not(release_id: nil) }
  scope("Without release") { |scope| scope.where(release_id: nil) }

  config.sort_order = "created_at_desc"

  sidebar "Summary", only: :index do
    dl style: "display:grid;grid-template-columns:1fr auto;gap:6px 12px;margin:0;" do
      dt { strong "Total" }
      dd { b WarpEngine::Download.count.to_s }

      dt { strong "Today" }
      dd { b WarpEngine::Download.where("created_at >= ?", Date.current.beginning_of_day).count.to_s }

      dt { strong "This week" }
      dd { b WarpEngine::Download.where("created_at >= ?", 1.week.ago).count.to_s }

      dt { strong "This month" }
      dd { b WarpEngine::Download.where("created_at >= ?", 1.month.ago).count.to_s }
    end
  end

  sidebar "Top 10 Files", only: :index do
    table_for WarpEngine::Download.group(:file_path)
                      .select("file_path, COUNT(*) as dl_count, MAX(created_at) as last_dl")
                      .order("dl_count DESC")
                      .limit(10) do
      column("File") { |row| span row.file_path.split("/").last, style: "font-family:monospace;font-size:11px;" }
      column("DL") { |row| row.dl_count }
    end
  end

  sidebar "Top 5 Software", only: :index do
    rows = WarpEngine::Download.joins(release: :software)
                   .group("softwares.title")
                   .order("count_all DESC")
                   .limit(5)
                   .count
    if rows.any?
      table_for rows do
        column("Software") { |title, _| title }
        column("DL") { |_, count| count }
      end
    else
      para "No data", style: "color:#999;font-style:italic;"
    end
  end

  index do
    id_column
    column(:file_path) { |d| span d.file_path.truncate(50), style: "font-family:monospace;font-size:12px;" }
    column("Software") { |d| d.release&.software ? link_to(d.release.software.title, admin_software_path(d.release.software)) : "–" }
    column("Release")  { |d| d.release&.version || "–" }
    column :ip_address
    column("User-Agent") { |d| d.user_agent&.truncate(40) }
    column("Referer")    { |d| d.referer&.truncate(40) }
    column :created_at
  end

  filter :file_path_cont, label: "File path"
  filter :release_software_title_cont, label: "Software"
  filter :ip_address_cont, label: "IP address"
  filter :user_agent_cont, label: "User-Agent"
  filter :referer_cont, label: "Referer"
  filter :created_at

  show do
    attributes_table do
      row :id
      row(:file_path) { |d| span d.file_path, style: "font-family:monospace;" }
      row("Software") do |d|
        if d.release&.software
          link_to d.release.software.title, admin_software_path(d.release.software)
        else
          "–"
        end
      end
      row("Release") do |d|
        if d.release
          link_to d.release.version, admin_software_release_path(d.release.software, d.release)
        else
          "–"
        end
      end
      row :ip_address
      row :user_agent
      row :referer
      row :created_at
      row :updated_at
    end
  end

  controller do
    def scoped_collection
      super.includes(release: :software)
    end
  end
end
