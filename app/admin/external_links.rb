ActiveAdmin.register WarpEngine::ExternalLink, as: "External Link" do
  permit_params :software_id, :label, :url, :kind, :ref

  menu false

  belongs_to :software

  batch_action :destroy, confirm: "Delete the selected records?" do |ids|
    scoped_collection.where(id: ids).find_each(&:soft_delete!)
    redirect_to collection_path, notice: "Deleted."
  end

  controller do
    def scoped_collection
      super.kept
    end

    def destroy
      resource.soft_delete!
      redirect_to collection_path, notice: "Deleted."
    end
  end

  index do
    selectable_column
    id_column
    column :label
    column(:url) { |el| link_to el.url, el.url, target: "_blank" }
    column :kind
    column :public
    column :created_at
    actions
  end

  form do |f|
    f.inputs do
      f.input :label
      f.input :url
      f.input :kind, as: :select, collection: WarpEngine::ExternalLink::KINDS, include_blank: false
      f.input :ref
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :label
      row(:url) { |el| link_to el.url, el.url, target: "_blank" }
      row :kind
      row :ref
      row :public
      row :verified_at
      row :verify_error
      row :created_at
      row :updated_at
    end
  end
end
