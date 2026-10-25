ActiveAdmin.register WarpEngine::PlatformLink, as: "Platform Link" do
  permit_params :name, :url, :platform, :position

  menu parent: "🌀 WarpEngine", priority: 5, label: "🔗 Platform Links"

  config.sort_order = "platform_asc"

  scope :all, default: true
  scope("TIC-80")     { |s| s.where(platform: "tic80") }
  scope("Ebitengine") { |s| s.where(platform: "ebitengine") }
  scope("LOVE")       { |s| s.where(platform: "love") }
  scope("C64")        { |s| s.where(platform: "c64") }
  scope("Plus/4")     { |s| s.where(platform: "plus4") }
  scope("Godot")      { |s| s.where(platform: "godot") }
  scope("Bevy")       { |s| s.where(platform: "bevy") }
  scope("Phaser")     { |s| s.where(platform: "phaser") }
  scope("DOS")        { |s| s.where(platform: "dos") }

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
