ActiveAdmin.register WarpEngine::Pipeline, as: "Pipeline" do
  actions :index, :show, :edit, :update

  menu parent: "🌀 WarpEngine", priority: 10, label: "🚀 Pipelines"

  config.sort_order = "repo_name_asc"
  config.batch_actions = false

  scope :all, default: true
  scope("Active")   { |s| s.where(active: true) }
  scope("Inactive") { |s| s.where(active: false) }

  WarpEngine::PlatformLink::SUPPORTED_PLATFORMS.each do |p|
    scope(p.capitalize) { |s| s.where(platform: p) }
  end

  index do
    id_column
    column :repo_owner
    column :repo_name
    column :platform
    column("Software") { |r| r.software ? link_to(r.software.title, admin_software_path(r.software)) : "-" }
    column(:active) { |r| status_tag(r.active ? "active" : "inactive", class: r.active ? "yes" : "no") }
    column("Pipeline") { |r|
      if r.last_pipeline_status
        status_tag r.last_pipeline_status,
                   class: r.last_pipeline_status == "success" ? "yes" : "no"
      else
        "-"
      end
    }
    column :last_pipeline_at
    actions defaults: true do |pipeline|
      if pipeline.active && WarpEngine.woodpecker_configured?
        item "Trigger", trigger_admin_pipeline_path(pipeline), method: :post, class: "member_link"
      end
    end
  end

  filter :repo_name
  filter :platform, as: :select, collection: WarpEngine::PlatformLink::SUPPORTED_PLATFORMS
  filter :active

  form do |f|
    f.inputs do
      f.input :platform, as: :select, collection: WarpEngine::PlatformLink::SUPPORTED_PLATFORMS
      f.input :software_id, as: :select,
              collection: WarpEngine::Software.order(:title).map { |s| [ s.title, s.id ] },
              include_blank: "- none -",
              hint: "One pipeline per software. Picking one that another pipeline already " \
                    "has moves the link here rather than refusing it."
    end
    f.actions
  end

  controller do
    # The reassignment itself is the model's job; this only makes it visible. Without a
    # word about it, the other pipeline loses its software with nothing on screen to say
    # that it happened.
    def update
      super
      taken = resource.software_taken_from
      return if taken.blank?

      flash[:notice] = [ flash[:notice], "Software taken from #{taken.join(', ')}." ].compact.join(" ")
    end
  end

  sidebar "Details", only: :show do
    attributes_table_for resource do
      row :id
      row :woodpecker_repo_id
      row :repo_owner
      row :repo_name
      row :platform
      row("Software") { |r| r.software ? link_to(r.software.title, admin_software_path(r.software)) : "-" }
      row(:active) { |r| status_tag(r.active ? "active" : "inactive", class: r.active ? "yes" : "no") }
      row :last_pipeline_status
      row :last_pipeline_at
      row :created_at
      row :updated_at
    end
  end

  show do
    panel "Pipelines" do
      if !WarpEngine.woodpecker_configured?
        para "Woodpecker is not configured. Set woodpecker_url and woodpecker_api_token in the WarpEngine initializer.",
             style: "color:#999;"
      elsif !resource.active
        para "This repository is inactive.", style: "color:#999;"
      else
        begin
          pipelines = WarpEngine::PipelineService.new.list_pipelines(resource, page: 1)
          if pipelines.is_a?(Array) && pipelines.any?
            table_for pipelines.first(10) do
              column("Number") { |p| p["number"] }
              column("Status") { |p| status_tag p["status"], class: p["status"] == "success" ? "yes" : "no" }
              column("Branch") { |p| p["branch"] }
              column("Message") { |p| p["message"]&.truncate(60) }
              # Woodpecker returns unix epoch seconds in "created"
              column("Created") { |p| p["created"] ? Time.zone.at(p["created"]).strftime("%Y-%m-%d %H:%M") : "-" }
            end
          else
            para "No pipelines found.", style: "color:#999;"
          end
        rescue => e
          para "Error fetching pipelines: #{e.message}", style: "color:red;"
        end
      end
    end
  end

  member_action :trigger, method: :post do
    pipeline = WarpEngine::Pipeline.find(params[:id])
    WarpEngine::PipelineService.new.trigger(pipeline)
    redirect_to resource_path(pipeline), notice: "Pipeline triggered for #{pipeline.full_name}"
  rescue => e
    redirect_to resource_path(pipeline), alert: "Trigger failed: #{e.message}"
  end

  collection_action :sync, method: :post do
    result = WarpEngine::PipelineSyncService.new.sync_all
    redirect_to collection_path,
      notice: "Synced: #{result[:created].size} new, #{result[:updated].size} updated, #{result[:deactivated].size} deactivated"
  rescue => e
    redirect_to collection_path, alert: "Sync failed: #{e.message}"
  end

  action_item :sync_repos, only: :index do
    if WarpEngine.woodpecker_configured?
      link_to "Sync from Woodpecker", sync_admin_pipelines_path, method: :post
    end
  end

  controller do
    def scoped_collection
      super.includes(:software)
    end
  end
end
