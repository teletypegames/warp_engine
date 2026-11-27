ActiveAdmin.register WarpEngine::CiRepository, as: "CI Repository" do
  actions :index, :show, :edit, :update

  permit_params :platform, :software_id

  menu parent: "WarpEngine", priority: 10, label: "CI Repositories"

  config.sort_order = "repo_name_asc"
  config.batch_actions = false

  scope :all, default: true
  scope("Active")   { |s| s.where(active: true) }
  scope("Inactive") { |s| s.where(active: false) }

  WarpEngine::Platform.all.each do |platform|
    scope(platform.label) { |s| s.where(platform: platform.name) }
  end

  index do
    id_column
    column :repo_owner
    column :repo_name
    column :platform
    column("Software") { |r| r.software ? link_to(r.software.title, admin_software_path(r.software)) : "-" }
    column(:active) { |r| status_tag(r.active ? "active" : "inactive", class: r.active ? "yes" : "no") }
    column("Last run") { |r|
      if r.last_pipeline_status
        status_tag r.last_pipeline_status,
                   class: r.last_pipeline_status == "success" ? "yes" : "no"
      else
        "-"
      end
    }
    column :last_pipeline_at
    actions defaults: true do |repository|
      if repository.active && WarpEngine.ci.configured?
        item "Trigger", trigger_admin_ci_repository_path(repository), method: :post, class: "member_link"
      end
    end
  end

  filter :repo_name
  filter :platform, as: :select, collection: -> { WarpEngine::Platform.names }
  filter :active

  form do |f|
    f.inputs do
      f.input :platform, as: :select, collection: -> { WarpEngine::Platform.names }
      f.input :software_id, as: :select,
              collection: WarpEngine::Software.kept.order(:title).map { |s| [ s.title, s.id ] },
              include_blank: "- none -",
              hint: "One repository per software. Picking one that another repository already " \
                    "has moves the link here — that repository is left without a software, " \
                    "and the move is written to the log."
    end
    f.actions
  end

  sidebar "Details", only: :show do
    attributes_table_for resource do
      row :id
      row("Repo id") { |r| r.remote_repo_id }
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
    panel "Pipeline runs" do
      if !WarpEngine.ci.configured?
        para "No CI provider is configured. Set c.ci_adapter in the WarpEngine initializer.",
             class: "we-muted"
      elsif !resource.active
        para "This repository is inactive.", class: "we-muted"
      else
        begin
          runs = WarpEngine::CiRepositoryService.new.runs(resource, page: 1)
          if runs.any?
            table_for runs.first(10) do
              column("Number") { |r| r.number }
              column("Status") { |r| status_tag r.status, class: r.success? ? "yes" : "no" }
              column("Branch") { |r| r.branch }
              column("Message") { |r| r.message&.truncate(60) }
              column("Created") { |r| r.created_at ? r.created_at.strftime("%Y-%m-%d %H:%M") : "-" }
            end
          else
            para "No pipeline runs found.", class: "we-muted"
          end
        rescue => e
          para "Error fetching pipeline runs: #{e.message}", style: "color:red;"
        end
      end
    end
  end

  member_action :trigger, method: :post do
    repository = WarpEngine::CiRepository.find(params[:id])
    WarpEngine::CiRepositoryService.new.trigger(repository)
    redirect_to resource_path(repository), notice: "Pipeline triggered for #{repository.full_name}"
  rescue => e
    redirect_to resource_path(repository), alert: "Trigger failed: #{e.message}"
  end

  collection_action :sync, method: [ :get, :post ] do
    if request.get?
      redirect_to collection_path
      return
    end
    result = WarpEngine::CiRepositorySyncService.new.sync_all
    redirect_to collection_path,
      notice: "Synced: #{result[:created].size} new, #{result[:updated].size} updated, #{result[:deactivated].size} deactivated"
  rescue => e
    redirect_to collection_path, alert: "Sync failed: #{e.message}"
  end

  action_item :sync_repos, only: :index do
    if WarpEngine.ci.configured?
      link_to "Sync from #{WarpEngine.ci.name}", sync_admin_ci_repositories_path, method: :post
    end
  end

  controller do
    def scoped_collection
      super.kept.includes(:software)
    end
  end
end
