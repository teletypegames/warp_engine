ActiveAdmin.register WarpEngine::RuntimeVersion, as: "Runtime" do
  actions :index, :show

  menu parent: "WarpEngine", priority: 11, label: "Runtimes"

  config.sort_order = "name_asc"
  config.batch_actions = false

  controller do
    def scoped_collection = super.kept.includes(:runtime_components)
  end

  index do
    id_column
    column :name
    column :version
    column :source
    column("Components") { |version| version.runtime_components.map { |component| "#{component.kind} #{component.key}" }.join(", ") }
    column("Size") { |version| number_to_human_size(version.size_bytes) }
    column("Releases") { |version| version.releases.count }
    column("Platforms") { |version| version.runtime&.platforms&.join(", ") }
    column :created_at
    actions
  end

  filter :name
  filter :version
  filter :source, as: :select, collection: -> { WarpEngine::RuntimeVersion::SOURCES }

  show do
    attributes_table do
      row :name
      row :version
      row :source
      row :path
      row("Size") { |version| number_to_human_size(version.size_bytes) }
      row("Components") { |version| version.runtime_components.map { |component| "#{component.kind} #{component.key}" }.join(", ") }
      row("Platforms") { |version| version.runtime&.platforms&.join(", ") }
      row :created_at
      row :updated_at
    end

    panel "Files" do
      table_for resource.file_digests.sort.map { |file, digest| { file: file, digest: digest } } do
        column("File") { |entry| entry[:file] }
        column("SHA-256") { |entry| content_tag(:code, entry[:digest]) }
      end
    end

    panel "Releases" do
      table_for resource.releases.includes(:software).order(created_at: :desc) do
        column("Software") { |release| link_to(release.software.title, admin_software_path(release.software)) }
        column :version
        column :web_binding
      end
    end
  end
end
