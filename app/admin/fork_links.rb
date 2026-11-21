ActiveAdmin.register WarpEngine::ForkLink, as: "Fork Link" do
  actions :index, :show, :destroy

  menu parent: "WarpEngine", priority: 13, label: "Fork Links",
       if: -> { WarpEngine::Forks.accept_announcements? || WarpEngine::ForkLink.kept.exists? }

  config.sort_order = "created_at_desc"
  config.batch_actions = false

  scope :all, default: true
  scope("Pending") { |scope| scope.where(status: "pending") }
  scope("Visible") { |scope| scope.where(status: "visible") }
  scope("Hidden")  { |scope| scope.where(status: "hidden") }
  scope("Gone")    { |scope| scope.where(status: "gone") }

  controller do
    def scoped_collection
      super.kept.includes(:software)
    end

    def destroy
      resource.soft_delete!
      redirect_to collection_path, notice: "Deleted."
    end
  end

  member_action :moderate, method: :post do
    status = params[:status].to_s
    if WarpEngine::ForkLink::STATUSES.include?(status)
      resource.update!(status: status)
      redirect_back fallback_location: resource_path(resource), notice: "#{resource.child_name}: #{status}"
    else
      redirect_back fallback_location: resource_path(resource), alert: "Unknown status #{status}"
    end
  end

  index do
    id_column
    column :created_at
    column("Software") { |link| link.software ? link_to(link.software.name, admin_software_path(link.software)) : "—" }
    column("Fork") { |link| link_to(link.child_title.presence || link.child_name, link.child_engine, target: "_blank", rel: "noopener") }
    column(:child_engine)
    column("Status") { |link| status_tag link.status, class: { "visible" => "yes", "gone" => "no" }[link.status] }
    column :checked_at
    column("Moderate") do |link|
      safe_join((%w[visible hidden] - [ link.status ]).map do |status|
        link_to(status == "visible" ? "Show" : "Hide", moderate_admin_fork_link_path(link, status: status), method: :post)
      end, " · ")
    end
    actions
  end

  filter :software, as: :select, collection: -> { WarpEngine::Software.kept.order(:name).map { |software| [ software.name, software.id ] } }
  filter :status, as: :select, collection: WarpEngine::ForkLink::STATUSES
  filter :child_engine_cont, label: "Engine"
  filter :created_at

  show title: proc { |link| link.child_title.presence || link.child_name } do
    attributes_table do
      row :id
      row :software
      row :child_engine
      row :child_name
      row :child_title
      row :status
      row :checked_at
      row :last_error
      row :created_at
      row :updated_at
    end
    para do
      safe_join((%w[visible hidden] - [ resource.status ]).map do |status|
        link_to(status == "visible" ? "Show on the software's page" : "Hide", moderate_admin_fork_link_path(resource, status: status), method: :post)
      end, " · ")
    end
  end
end
