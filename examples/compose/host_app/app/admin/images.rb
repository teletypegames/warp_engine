ActiveAdmin.register Image do
  permit_params :file_upload

  menu parent: "WarpEngine", priority: 5, label: "Images"

  index do
    selectable_column
    id_column
    column :original_filename
    column :content_type
    column(:preview) { |img| image_tag(img.url, style: "max-height:60px;max-width:120px;object-fit:contain;") }
    column :created_at
    actions
  end

  filter :original_filename
  filter :content_type

  show do
    attributes_table do
      row :id
      row :original_filename
      row :content_type
      row(:preview) { |img| image_tag(img.url, style: "max-height:300px;max-width:100%;object-fit:contain;") }
      row :created_at
    end
  end

  form html: { multipart: true } do |f|
    f.inputs { f.input :file_upload, as: :file, label: "Image file" }
    f.actions
  end
end
