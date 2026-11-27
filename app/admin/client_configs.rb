ActiveAdmin.register WarpEngine::ClientConfig, as: "Store Engine" do
  permit_params :client, :software_name, :name, :store_key, :subfolder, :logo_urls, :pinned_version, statuses: []

  menu parent: "WarpEngine", priority: 5, label: "Store Engines"

  config.sort_order = "client_asc"
  config.filters = false

  index do
    column :client
    column(:software) { |record| record.software_name.presence || WarpEngine::Clients.find(record.client)&.software }
    column :name
    column :store_key
    column :pinned_version
    column(:installer) { |record| "/api/stores/#{record.client}/install.sh" }
    actions
  end

  show do
    attributes_table do
      row :client
      row :software_name
      row :name
      row :store_key
      row :subfolder
      row(:statuses) { |record| Array(record.statuses).join(", ") }
      row(:logo_urls) { |record| safe_join(Array(record.logo_urls), tag.br) }
      row :pinned_version
      row(:installer) { |record| "curl -fsSL #{request.base_url}/api/stores/#{record.client}/install.sh | sh" }
      row :updated_at
    end
  end

  form do |f|
    f.inputs "Store engine" do
      f.input :client, as: :select, collection: WarpEngine::Clients.keys, include_blank: false
      f.input :software_name, hint: "The catalog software the engine is released as; blank: we-batocera or we-retroarch"
      f.input :name, hint: "The store's name on the machine; blank: the catalog's store name or host"
      f.input :store_key, label: "Store id", hint: "Folder and file names on the machine; blank: from the host"
      f.input :subfolder, hint: "Where the games go; blank: the store id"
      f.input :statuses, as: :check_boxes, collection: WarpEngine::SoftwareStatus.keys,
                         hint: "What the store installs; none: the statuses shown by default"
      f.input :logo_urls, as: :text, input_html: { rows: 3, value: Array(f.object.logo_urls).join("\n") },
                          hint: "One http(s) URL per line, .png or .svg"
      f.input :pinned_version, hint: "Every machine runs this release instead of the newest stable one"
    end
    f.actions
  end
end
