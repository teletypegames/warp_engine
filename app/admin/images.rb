ActiveAdmin.register WarpEngine::Image, as: "Image" do
  permit_params :file_upload

  menu parent: "🌀 WarpEngine", priority: 5, label: "🖼️ Images"

  used_ids = -> {
    WarpEngine::SoftwareImage.unscope(:order).distinct.pluck(:image_id) +
      WarpEngine.config.image_owners.flat_map { |o| o[:image_ids].call }
  }

  scope :all, default: true
  scope("In use") { |scope| scope.where(id: used_ids.call) }
  scope("Orphan") { |scope| scope.where.not(id: used_ids.call) }

  batch_action :delete_orphans, confirm: "Delete all selected orphan images and their files?" do |ids|
    orphan_ids = ids.map(&:to_i) - used_ids.call
    WarpEngine::Image.where(id: orphan_ids).find_each do |img|
      File.delete(img.file_path) if File.exist?(img.file_path)
      img.destroy
    end
    redirect_to admin_images_path, notice: "Deleted #{orphan_ids.size} orphan image(s)."
  end

  index do
    selectable_column
    id_column
    column :original_filename
    column :content_type
    column(:preview) do |img|
      if File.exist?(img.file_path)
        image_tag("/api/image/#{img.id}", style: "max-height:60px;max-width:120px;object-fit:contain;")
      end
    end
    column(:usage) do |img|
      uses = []
      uses << "#{img.software_images.size} software(s)" if img.software_images.any?
      uses.concat(WarpEngine.config.image_owners.filter_map { |o| o[:usage_label].call(img) })
      uses.any? ? uses.join(", ") : status_tag("orphan", class: "warning")
    end
    column :created_at
    actions
  end

  filter :original_filename
  filter :content_type

  show do
    attributes_table do
      row :id
      row :original_filename
      row :filename
      row :content_type
      row(:preview) do |img|
        if File.exist?(img.file_path)
          image_tag("/api/image/#{img.id}", style: "max-height:300px;max-width:100%;object-fit:contain;")
        else
          "File not found on disk"
        end
      end
      row :created_at
      row :updated_at
    end
  end

  form html: { multipart: true } do |f|
    f.inputs do
      f.input :file_upload, as: :file, label: "Image File"
    end
    f.actions
  end

  controller do
    def scoped_collection
      super.includes(:software_images)
    end
  end
end
