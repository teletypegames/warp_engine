ActiveAdmin.register WarpEngine::Software, as: "Software" do
  permit_params do
    [
      :name, :title, :author, :desc, :story,
      :license, :platform, :status, :category, :highlighted,
      { software_images_attributes: [ :id, :image_id, :is_default, :position, :file_upload, :_destroy ] },
      { external_links_attributes: [ :id, :label, :url, :_destroy ] },
      { releases_attributes: [ :id, :version, :_destroy,
                               { release_assets_attributes: [ :id, :kind, :path, :_destroy ] } ] }
    ] + WarpEngine::AdditionalResource.permitted_params_for(:software)
  end

  menu parent: "🌀 WarpEngine", priority: 2, label: "🎮 Softwares"

  actions :all, except: [ :edit ]

  config.sort_order = "title_asc"

  index do
    selectable_column
    id_column
    column :name do |sw|
      link_to sw.name, admin_software_path(sw)
    end
    column :title
    column :platform
    column :status do |sw|
      status_tag sw.status
    end
    column :category
    column :highlighted
    column(:releases) { |sw| sw.releases.size }
    column(:image) do |sw|
      si = sw.software_images.detect(&:is_default?) || sw.software_images.first
      if si&.image && WarpEngine::Images.available?(si.image)
        image_tag WarpEngine::Images.url_for(si.image_id), style: "max-height:40px;max-width:80px;object-fit:contain;"
      end
    end
    column :created_at
    actions
  end

  filter :name
  filter :title
  filter :author
  filter :platform, as: :select, collection: WarpEngine::Platform.names
  filter :status,   as: :select, collection: -> { WarpEngine::SoftwareStatus.keys }
  filter :category
  filter :highlighted

  sidebar "Quick Links", only: :show, priority: 0 do
    if WarpEngine.config.site_url.present?
      catalog_url = "#{WarpEngine.config.site_url.chomp('/')}/catalog/#{resource.name}"

      div style: "margin-bottom:8px;" do
        a href: catalog_url, target: "_blank", style: "display:inline-flex;align-items:center;gap:6px;font-weight:bold;color:#5850ec;" do
          span "🌐", style: "font-size:16px;"
          text_node "View on site"
        end
      end
    end

    if resource.pipeline
      div style: "margin-bottom:8px;" do
        a href: admin_pipeline_path(resource.pipeline), style: "display:inline-flex;align-items:center;gap:6px;font-weight:bold;color:#5850ec;" do
          span "🚀", style: "font-size:16px;"
          text_node "Pipelines"
        end
      end
    end
  end

  sidebar "Download Statistics", only: :show do
    sw = resource
    stats = WarpEngine::DownloadStatsService.new.for_software(sw)

    div style: "margin-bottom:12px;" do
      strong "Total downloads: "
      span stats[:total].to_s, style: "font-size:18px;font-weight:bold;"
    end

    stats[:releases].each do |rel|
      div style: "margin-bottom:16px;" do
        h4 do
          text_node link_to("v#{rel[:version]}", admin_release_path(rel[:release_id]))
          span " (#{rel[:downloads]})", style: "color:#666;"
        end
        if rel[:files].any?
          table_for rel[:files] do
            column("File") { |row| span row[:file_path].split("/").last, style: "font-family:monospace;font-size:11px;" }
            column("DL") { |row| row[:downloads] }
            column("Last") { |row| row[:last_download_at]&.strftime("%m-%d") }
          end
        else
          para "No downloads", style: "color:#999;font-style:italic;"
        end
      end
    end
  end

  show title: proc { |sw| sw.title } do
    active_admin_form_for [ :admin, resource ], url: admin_software_path(resource), html: { method: :put, multipart: true } do |f|
      f.inputs "Details" do
        f.input :name
        f.input :title
        f.input :author
        f.input :platform, as: :select, collection: WarpEngine::Platform.names
        f.input :status,   as: :select, collection: WarpEngine::SoftwareStatus.ensured.map { |s| [ s.label, s.key ] }
        f.input :category, as: :datalist, collection: WarpEngine::SoftwareCategory.ordered.pluck(:key),
                hint: "A key from the category vocabulary; a new word is added to it for review. Empty means uncategorised."
        f.input :highlighted
        f.input :license
        f.input :desc,  as: :text, input_html: { rows: 4 }
        f.input :story, as: :text, input_html: { rows: 8 }
      end

      f.inputs "Images" do
        f.has_many :software_images, allow_destroy: true, new_record: true do |si|
          img_hint = if si.object.image_id.present?
            si.template.image_tag(WarpEngine::Images.url_for(si.object.image_id), style: "max-height:80px;max-width:160px;object-fit:contain;margin-top:6px;").html_safe
          end
          si.input :image_id, as: :select, label: "Image",
                   collection: WarpEngine::Images.select_options,
                   include_blank: "— select —",
                   hint: img_hint
          si.input :file_upload, as: :file, label: "Upload new image"
          si.input :is_default, as: :boolean
          si.input :position, as: :number, input_html: { min: 0 }
        end
      end

      f.inputs "External Links" do
        f.has_many :external_links, allow_destroy: true, new_record: true do |el|
          el.input :label
          el.input :url
        end
      end

      f.inputs "Releases" do
        f.has_many :releases, allow_destroy: true, new_record: true do |r|
          r.input :version
          r.has_many :release_assets, allow_destroy: true, new_record: true do |ra|
            ra.input :kind, as: :select, collection: WarpEngine::ReleaseAsset::KINDS, include_blank: false
            ra.input :path
          end
        end
      end

      WarpEngine::AdditionalResource.for(:software).each do |extra|
        f.inputs extra.label do
          if extra.multiple
            f.has_many extra.association, allow_destroy: true, new_record: true do |nested|
              extra.render(nested)
            end
          else
            f.semantic_fields_for extra.association do |nested|
              extra.render(nested)
            end
          end
        end
      end

      f.actions
    end
  end

  controller do
    def scoped_collection
      super.kept.includes({ releases: :release_assets }, software_images: :image)
    end

    def find_resource
      scoped_collection.find(params[:id])
    end
  end
end
