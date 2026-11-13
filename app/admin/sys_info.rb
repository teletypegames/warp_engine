ActiveAdmin.register_page "SysInfo" do
  menu parent: "🌀 WarpEngine", priority: 20, label: "ℹ️ SysInfo"

  content title: "SysInfo" do
    para "The engine's configuration as it runs now, read from the host's initializer and the environment. Secrets show only whether they are set.",
         class: "warp-engine-sysinfo-intro"

    WarpEngine::SysInfo.new.sections.each do |section|
      panel section.title do
        para section.intro if section.intro.present?

        if section.rows.any?
          table_for section.rows, class: "warp-engine-sysinfo-settings" do
            column("Setting") { |row| strong row[0] }
            column("Value") { |row| row[1] }
          end
        end

        section.tables.each do |table|
          h4 table.title if table.title
          table_for table.rows do
            table.columns.each_with_index { |name, index| column(name) { |row| row[index] } }
          end
        end
      end
    end
  end
end
