ActiveAdmin.register WarpEngine::ExternalLink, as: "External Link" do
  permit_params :software_id, :label, :url

  menu false

  belongs_to :software

  controller do
    def scoped_collection
      super.kept
    end
  end

  index do
    selectable_column
    id_column
    column :label
    column(:url) { |el| link_to el.url, el.url, target: "_blank" }
    column :created_at
    actions
  end

  form do |f|
    f.inputs do
      f.input :label
      f.input :url
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :label
      row(:url) { |el| link_to el.url, el.url, target: "_blank" }
      row :created_at
      row :updated_at
    end
  end
end
