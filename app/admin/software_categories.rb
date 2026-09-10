ActiveAdmin.register WarpEngine::SoftwareCategory, as: "Software Category" do
  permit_params :key, :label, :position, :needs_review

  menu parent: "🌀 WarpEngine", priority: 4, label: "🗂 Categories"

  config.sort_order = "position_asc"

  scope :all, default: true
  scope("Needs review") { |scope| scope.where(needs_review: true) }

  index do
    selectable_column
    column :position
    column :key
    column :label
    column :needs_review
    column(:softwares) { |category| WarpEngine::Software.where(category: category.key).count }
    actions
  end

  filter :key
  filter :label
  filter :needs_review

  form do |f|
    f.inputs "Category" do
      f.input :key, hint: "The value a software's category holds — what metadata.json writes"
      f.input :label
      f.input :position
      f.input :needs_review, hint: "Set when a publish brought a word nobody has named yet"
    end
    f.actions
  end
end
