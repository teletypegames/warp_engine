ActiveAdmin.register_page "CI Dashboard" do
  menu priority: 11, label: "🚀 CI Dashboard"

  content do
    if WarpEngine.woodpecker_configured?
      begin
        entries = WarpEngine::CiPipelineService.new.dashboard
      rescue => e
        entries = []
        div class: "flash flash_alert" do
          "Error connecting to Woodpecker: #{e.message}"
        end
      end

      entries.group_by { |e| e[:repo].platform }.sort.each do |platform, group|
        panel platform.titleize do
          table_for group do
            column("Repository") { |e| link_to e[:repo].full_name, admin_ci_repository_path(e[:repo]) }
            column("Software")   { |e| e[:repo].software ? link_to(e[:repo].software.title, admin_software_path(e[:repo].software)) : "-" }
            column("Status")     { |e|
              if e[:pipeline]
                status_tag e[:pipeline]["status"],
                           class: e[:pipeline]["status"] == "success" ? "ok" : "error"
              else
                status_tag "unknown", class: "warning"
              end
            }
            column("Branch")  { |e| e.dig(:pipeline, "branch") || "-" }
            column("When")    { |e| e.dig(:pipeline, "created_at") || "-" }
            column("Actions") { |e|
              if e[:repo].active
                text_node link_to("Trigger", trigger_admin_ci_repository_path(e[:repo]),
                                  method: :post, class: "member_link")
              end
            }
          end
        end
      end

      if entries.empty?
        para "No CI repositories tracked. Sync repos from the CI Repos page.",
             style: "color:#999;text-align:center;padding:40px 0;"
      end
    else
      para "Woodpecker is not configured. Set woodpecker_url and woodpecker_api_token in the WarpEngine initializer.",
           style: "color:#999;text-align:center;padding:40px 0;"
    end
  end
end
