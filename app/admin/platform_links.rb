ActiveAdmin.register WarpEngine::PlatformLink, as: "Platform Link" do
  permit_params :name, :url, :platform, :position

  menu parent: "🌀 WarpEngine", priority: 5, label: "🔗 Platform Links"

  config.sort_order = "platform_asc"

  scope :all, default: true
  WarpEngine::Platform.all.each do |platform|
    scope(platform.label) { |s| s.where(platform: platform.name) }
  end

  controller do
    def scoped_collection
      super.kept
    end
  end

  index do
    selectable_column
    id_column
    column :platform
    column :name
    column(:url) { |pl| link_to pl.url, pl.url, target: "_blank" }
    column :position
    column :created_at
    actions
  end

  filter :platform, as: :select, collection: WarpEngine::Platform.names
  filter :name

  form do |f|
    f.inputs do
      f.input :platform, as: :select, collection: WarpEngine::Platform.names
      f.input :name
      f.input :url
      f.input :position, as: :number, input_html: { min: 0 }
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :platform
      row :name
      row(:url) { |pl| link_to pl.url, pl.url, target: "_blank" }
      row :position
      row :created_at
      row :updated_at
    end
  end
end
