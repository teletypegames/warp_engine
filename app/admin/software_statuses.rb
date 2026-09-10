ActiveAdmin.register WarpEngine::SoftwareStatus, as: "Software Status" do
  permit_params :key, :label, :position, :default_visible, :badge

  menu parent: "🌀 WarpEngine", priority: 3, label: "🏷 Statuses"

  config.sort_order = "position_asc"

  index do
    selectable_column
    column :position
    column :key
    column :label
    column :default_visible
    column :badge
    column(:softwares) { |status| WarpEngine::Software.where(status: status.key).count }
    actions
  end

  filter :key
  filter :label
  filter :default_visible

  form do |f|
    f.inputs "Status" do
      f.input :key, hint: "Lowercase letters, digits, - and _; this is the value a software's status holds"
      f.input :label
      f.input :position
      f.input :default_visible, hint: "Whether a store lists this status when it has no preference of its own"
      f.input :badge, hint: "A style hint for the label (released, demo, development); empty for a plain badge"
    end
    f.actions
  end
end
