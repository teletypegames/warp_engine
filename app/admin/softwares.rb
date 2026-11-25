ActiveAdmin.register WarpEngine::Software, as: "Software" do
  permit_params do
    [
      :name, :title, :author, :desc, :story,
      :license, :platform, :status, :category, :highlighted, :shelf_name, :sync_enabled, { disabled_kinds: [] },
      :forks_allowed, :fork_of_engine, :fork_of_name, :fork_of_version, :fork_of_repo,
      { software_images_attributes: [ :id, :image_id, :is_default, :position, :file_upload, :_destroy ] },
      { external_links_attributes: [ :id, :label, :url, :kind, :ref, :_destroy ] },
      { releases_attributes: [ :id, :version, :_destroy,
                               { release_assets_attributes: [ :id, :kind, :path, :_destroy ] } ] }
    ] + WarpEngine::AdditionalResource.permitted_params_for(:software)
  end

  menu parent: "WarpEngine", priority: 2, label: "Softwares"

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

      div class: "we-quick-link" do
        a href: catalog_url, target: "_blank" do
          text_node WarpEngine::AdminIcons.svg(:globe)
          text_node "View on site"
        end
      end
    end

    if resource.pipeline
      div class: "we-quick-link" do
        a href: admin_pipeline_path(resource.pipeline) do
          text_node WarpEngine::AdminIcons.svg(:branch)
          text_node "Pipeline"
        end
      end
    end
  end

  sidebar "Sync", only: :show, if: -> { WarpEngine::SyncPeer.kept.exists? } do
    lines = WarpEngine::SyncService.new.status(resource)
    if lines.any?
      table_for lines do
        column("Peer") { |line| link_to line.peer.label, admin_sync_peer_path(line.peer) }
        column("Dir") { |line| line.direction == "outbound" ? "out" : "in" }
        column("Last") do |line|
          if line.event
            span(status_tag(line.event.status, class: line.event.succeeded? ? "yes" : (line.event.failed? ? "no" : nil)))
            span "#{line.event.version} · #{line.event.created_at&.strftime('%m-%d %H:%M')}", class: "we-muted"
          else
            span "never", class: "we-muted"
          end
        end
      end
      held = lines.find { |line| line.direction == "outbound" && line.reason }
      para "Not pushed: #{held.reason}", class: "we-muted" if held
      if WarpEngine::Sync.outbound? && lines.any? { |line| line.direction == "outbound" }
        para link_to("Push now", admin_sync_runner_path(softwares: resource.name, mode: "latest", filtered: "1", skip_existing: "1",
                                                        channels: WarpEngine::Sync.config.outbound.allowed_channels,
                                                        peer_ids: lines.select { |line| line.direction == "outbound" }.map { |line| line.peer.id }))
      end
    else
      para "No peer takes part in sync", class: "we-muted"
    end
    para link_to("All sync events of #{resource.name}", admin_sync_events_path(q: { software_id_eq: resource.id })) if WarpEngine::Sync.config.events?
  end

  sidebar "Forks", only: :show, if: -> { resource.fork? || WarpEngine::Current.fork_count(resource).positive? || resource.fork_links.exists? } do
    para "Fork of #{resource.fork_of_name} (#{resource.fork_of_engine})" if resource.fork?
    forks = WarpEngine::ForkService.new.forks(resource)
    para "#{forks.size} listed fork(s)"
    pending = resource.fork_links.where(status: "pending").count
    para link_to("#{pending} waiting for moderation", admin_fork_links_path(q: { software_id_eq: resource.id, status_eq: "pending" })) if pending.positive?
    para link_to("All announced forks", admin_fork_links_path(q: { software_id_eq: resource.id })) if resource.fork_links.exists?
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
          span " (#{rel[:downloads]})", class: "we-muted"
        end
        if rel[:files].any?
          table_for rel[:files] do
            column("File") { |row| span row[:file_path].split("/").last, style: "font-family:monospace;font-size:11px;" }
            column("DL") { |row| row[:downloads] }
            column("Last") { |row| row[:last_download_at]&.strftime("%m-%d") }
          end
        else
          para "No downloads", class: "we-muted"
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
        f.input :shelf_name, hint: "File name on a shelf (A-Z, 0-9, -); empty uses the name"
        f.input :disabled_kinds, as: :check_boxes, label: "Disabled kinds",
                collection: WarpEngine::Platform.find(resource.platform, app: resource.app)&.disableable_kinds || [],
                hint: "Not built, not uploaded, left out of the catalog; web: no web play. The CI marker's disable: key sets them on publish."
        f.input :license
        f.input :desc,  as: :text, input_html: { rows: 4 }
        f.input :story, as: :text, input_html: { rows: 8 }
      end

      if WarpEngine::Sync.config.outbound.software_switch?
        opt_in = WarpEngine::Sync.config.outbound.software_switch == :opt_in
        f.inputs "Sync" do
          f.input :sync_enabled, as: :select, label: "Sync to other engines",
                  collection: [ [ "Default (#{opt_in ? 'off' : 'on'})", "" ], [ "On", true ], [ "Off", false ] ],
                  include_blank: false,
                  hint: "Whether the releases of this software go to the sync peers. The denied_* lists of the outbound settings still win."
        end
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
          state = { true => "public", false => "private or unreachable", nil => "not checked yet" }[el.object.public]
          el.input :label
          el.input :url, hint: (el.object.source? && el.object.persisted? ? "Source check: #{state} #{el.object.verify_error}".strip : nil)
          el.input :kind, as: :select, collection: WarpEngine::ExternalLink::KINDS, include_blank: false,
                          hint: "source: the git repository the software is built from (one per software)"
          el.input :ref, hint: "Branch or tag of a source; empty for the default branch"
        end
      end

      f.inputs "Forks" do
        f.input :forks_allowed, label: "Allow forks", hint: "The developer tools offer a fork when the source repository is public"
        f.input :fork_of_engine, label: "Fork of: engine", hint: "Base URL of the parent's engine; empty when this is no fork"
        f.input :fork_of_name, label: "Fork of: name"
        f.input :fork_of_version, label: "Fork of: version"
        f.input :fork_of_repo, label: "Fork of: repository"
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

  batch_action :destroy, confirm: "Delete the selected records?" do |ids|
    scoped_collection.where(id: ids).find_each(&:soft_delete!)
    redirect_to collection_path, notice: "Deleted."
  end

  controller do
    def scoped_collection
      super.kept.includes({ releases: :release_assets }, software_images: :image)
    end

    def find_resource
      scoped_collection.find(params[:id])
    end

    def build_new_resource
      attributes = resource_params.first || {}
      WarpEngine::Software.revive(name: attributes[:name]).tap { |software| software.assign_attributes(attributes) }
    end

    def destroy
      resource.soft_delete!
      redirect_to collection_path, notice: "Deleted."
    end
  end
end
