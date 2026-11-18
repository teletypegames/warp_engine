ActiveAdmin.register WarpEngine::SyncPeer, as: "Sync Peer" do
  actions :index, :show, :new, :create, :edit, :update, :destroy
  permit_params :label, :transport, :secret, :outbound_enabled, :inbound_enabled, transport_options: {}

  menu parent: "WarpEngine", priority: 11, label: "Sync Peers"

  config.sort_order = "label_asc"
  config.batch_actions = false

  scope :all, default: true
  scope("Outbound") { |scope| scope.where(outbound_enabled: true) }
  scope("Inbound")  { |scope| scope.where(inbound_enabled: true) }

  index do
    id_column
    column :label
    column(:transport) { |peer| peer.transport_class&.label || peer.transport }
    column("Target") { |peer| code peer.target }
    column("Outbound") { |peer| status_tag(peer.outbound_enabled ? "on" : "off", class: peer.outbound_enabled ? "yes" : "no") }
    column("Inbound") { |peer| status_tag(peer.inbound_enabled && peer.inbound_token_id ? "on" : "off", class: peer.inbound_enabled && peer.inbound_token_id ? "yes" : "no") }
    column :last_synced_at
    column(:last_error) { |peer| peer.last_error.to_s.truncate(80) }
    actions
  end

  filter :label_cont, label: "Label"
  filter :transport, as: :select, collection: -> { WarpEngine::Sync::Transports.keys }
  filter :outbound_enabled
  filter :inbound_enabled
  filter :last_synced_at

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)
    current = f.object.transport.presence || "http"
    f.inputs "Peer" do
      f.input :label
      f.input :outbound_enabled, label: "Push our releases to it (outbound)",
                                 hint: WarpEngine::Sync.outbound? ? nil : "Outbound sync is off in the initializer (sync { outbound { enabled true } })."
      f.input :inbound_enabled, label: "Accept its pushes (inbound)",
                                hint: "It pushes with a token issued on this page. #{'Inbound sync is off in the initializer (sync { inbound { enabled true } }).' unless WarpEngine::Sync.inbound?}"
      f.input :transport, as: :select, include_blank: false,
                          collection: WarpEngine::Sync::Transports.classes.map { |klass| [ klass.label, klass.key ] },
                          input_html: { "data-we-transport-select": true }
    end
    WarpEngine::Sync::Transports.classes.each do |klass|
      next if klass.options.empty?

      f.inputs "#{klass.label}: how to reach it", class: "inputs we-transport", "data-we-transport": klass.key,
                                                  style: (klass.key == current ? nil : "display:none") do
        klass.options.each do |option|
          if option.secret
            f.input :secret, as: option.type == :text ? :text : :password, label: option.label, required: f.object.new_record? && option.required,
                             hint: "#{option.hint} Leave empty to keep the stored one.",
                             input_html: { name: "sync_peer[secret]", id: "sync_peer_secret_#{klass.key}", disabled: klass.key != current,
                                           value: "", rows: 4 }
          else
            f.input :"transport_option_#{option.name}", label: option.label, required: option.required, hint: option.hint,
                                                         as: option.type == :boolean ? :boolean : :string,
                                                         input_html: { name: "sync_peer[transport_options][#{option.name}]",
                                                                       id: "sync_peer_transport_options_#{klass.key}_#{option.name}",
                                                                       disabled: klass.key != current }
          end
        end
      end
    end
    f.actions
  end

  action_item :check, only: :show do
    link_to "Check connection", check_admin_sync_peer_path(resource), method: :post if resource.outbound_enabled
  end

  action_item :push_latest, only: :show do
    if WarpEngine::Sync.outbound? && resource.outbound_enabled
      link_to "Push latest releases", push_admin_sync_peer_path(resource), method: :post,
              data: { confirm: "Queue a push of the newest allowed release of every software to #{resource.label}?" }
    end
  end

  action_item :full_sync, only: :show do
    if WarpEngine::Sync.outbound? && resource.outbound_enabled
      link_to "Full sync", push_admin_sync_peer_path(resource, all: 1), method: :post,
              data: { confirm: "Queue a push of every allowed release of every software to #{resource.label}, oldest first? " \
                               "This can be a lot of uploads." }
    end
  end

  action_item :runner, only: :show do
    if resource.outbound_enabled
      link_to "Sync Runner", admin_sync_runner_path(peer_ids: [ resource.id ], mode: "latest", filtered: "1", skip_existing: "1",
                                                    channels: WarpEngine::Sync.config.outbound.allowed_channels)
    end
  end

  action_item :inbound_token, only: :show do
    if resource.inbound_enabled
      link_to resource.inbound_token_id ? "Issue new inbound token" : "Issue inbound token", issue_inbound_token_admin_sync_peer_path(resource),
              method: :post, data: { confirm: resource.inbound_token_id ? "The current inbound token of #{resource.label} stops working. Continue?" : nil }
    end
  end

  member_action :check, method: :post do
    result = WarpEngine::SyncService.new.check(resource)
    version = result.version ? " (WarpEngine #{result.version})" : ""
    flash_key = result.ok ? :notice : :alert
    redirect_to resource_path(resource), flash_key => "#{resource.label}: #{result.message}#{version}."
  end

  member_action :push, method: :post do
    all = params[:all].present?
    WarpEngine::SyncBackfillJob.perform_later(resource.id, nil, all)
    redirect_to resource_path(resource), notice: "The #{all ? 'full sync' : 'pushes of the latest releases'} to #{resource.label} " \
                                                 "is being queued; follow it under Recent events."
  end

  member_action :issue_inbound_token, method: :post do
    token = resource.issue_inbound_token!
    session[:warp_engine_plain_token] = token.plain_token
    redirect_to resource_path(resource), notice: "Inbound token issued. Give it to #{resource.label}: on their side it is the token of the peer that points here."
  end

  show do
    if (plain = controller.instance_variable_get(:@plain_token))
      panel "Inbound token: shown only once, copy it now", class: "we-panel-warn" do
        pre plain, class: "we-secret"
      end
    end
    columns do
      column do
        panel "Outbound: we push to it" do
          attributes_table_for resource do
            row("Pushes") { |peer| status_tag(peer.outbound_enabled ? "on" : "off", class: peer.outbound_enabled ? "yes" : "no") }
            row(:transport) { |peer| peer.transport_class&.label || peer.transport }
            row("Target") { |peer| code peer.target }
            row("Secret") { |peer| peer.secret_prefix ? code("#{peer.secret_prefix}… (stored encrypted)") : "none" }
            row :last_synced_at
            row :last_error
          end
        end
      end
      column do
        panel "Inbound: it pushes to us" do
          attributes_table_for resource do
            row("Accepted") { |peer| status_tag(peer.accepts_inbound? ? "yes" : "no", class: peer.accepts_inbound? ? "yes" : "no") }
            row("Inbound token") { |peer| peer.inbound_token ? code("#{peer.inbound_token.token_prefix}…") : "none issued" }
            row("Last used") { |peer| peer.inbound_token&.last_used_at }
            row("Releases from it") { |peer| peer.releases.kept.count }
          end
        end
      end
    end

    if WarpEngine::Sync.config.events?
      panel "Recent events" do
        events = resource.sync_events.recent.includes(:software).limit(25)
        if events.any?
          table_for events do
            column("When", &:created_at)
            column("Direction", &:direction)
            column("Software") { |event| event.software ? link_to(event.software_name, admin_software_path(event.software)) : event.software_name }
            column("Version", &:version)
            column("Status") { |event| status_tag event.status, class: event.succeeded? ? "yes" : (event.failed? ? "no" : nil) }
            column("Step", &:step)
            column("Code", &:http_status)
            column("Message") { |event| event.message.to_s.truncate(120) }
          end
        else
          para "No events yet", class: "we-muted"
        end
      end
    end
  end

  controller do
    def scoped_collection
      super.kept
    end

    def show
      @plain_token = session.delete(:warp_engine_plain_token)
      show!
    end

    def destroy
      resource.inbound_token&.revoke!
      resource.soft_delete!
      redirect_to collection_path, notice: "Sync peer deleted; its inbound token is revoked."
    end
  end
end
