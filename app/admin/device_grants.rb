ActiveAdmin.register WarpEngine::DeviceGrant, as: "Device Sign-in" do
  actions :index, :show

  menu parent: "🌀 WarpEngine", priority: 10, label: "📱 Device Sign-ins",
       if: proc { WarpEngine.identity_configured? }

  config.sort_order = "created_at_desc"
  config.batch_actions = false

  scope :all, default: true
  scope("Pending")  { |scope| scope.where(approved_at: nil, denied_at: nil).where(expires_at: Time.current..) }
  scope("Approved") { |scope| scope.where.not(approved_at: nil) }
  scope("Denied")   { |scope| scope.where.not(denied_at: nil) }

  index do
    id_column
    column("Code") { |g| code g.formatted_user_code, style: "font-family:monospace;" }
    column("Device") { |g| g.client_name }
    column("State") { |g| status_tag g.state.to_s }
    column("Who") do |g|
      next "—" if g.subject_id.blank?

      subject = g.subject
      subject.try(:email) || subject.try(:name) || "#{g.subject_type} ##{g.subject_id}"
    end
    column :expires_at
    column :created_at
  end

  filter :client_name_cont, label: "Device"
  filter :created_at
  filter :expires_at

  show do
    attributes_table do
      row("User code") { |g| code g.formatted_user_code, style: "font-family:monospace;" }
      row("Device") { |g| g.client_name }
      row("State") { |g| status_tag g.state.to_s }
      row("Who") do |g|
        next "—" if g.subject_id.blank?

        subject = g.subject
        subject.try(:email) || subject.try(:name) || "#{g.subject_type} ##{g.subject_id}"
      end

      row("Token") do |g|
        token = g.application_token
        next "—" if token.nil?

        link_to "#{token.token_prefix}… (#{token.name})", admin_application_token_path(token)
      end
      row :approved_at
      row :denied_at
      row :expires_at
      row :created_at
    end
  end
end
