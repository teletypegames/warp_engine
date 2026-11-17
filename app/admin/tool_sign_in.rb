ActiveAdmin.register_page "Tool Sign In" do
  menu false

  content title: "Tool sign-in" do
    code = params[:code].to_s
    grant = code.present? ? WarpEngine::DeviceGrant.find_pending_by_user_code(code) : nil
    render "warp_engine/admin/tool_sign_in", code: code, grant: grant&.tool? ? grant : nil
  end

  page_action :approve, method: :post do
    WarpEngine::DeviceGrantService.new.approve_tool(user_code: params[:code], admin: current_active_admin_user)
    redirect_to admin_tool_sign_in_path, notice: "Signed in. You can return to your tool."
  rescue WarpEngine::DeviceGrantService::UnknownCode
    redirect_to admin_tool_sign_in_path, alert: "No pending tool sign-in has this code."
  end

  page_action :deny, method: :post do
    WarpEngine::DeviceGrantService.new.deny_tool(user_code: params[:code])
    redirect_to admin_tool_sign_in_path, notice: "Sign-in denied."
  rescue WarpEngine::DeviceGrantService::UnknownCode
    redirect_to admin_tool_sign_in_path, alert: "No pending tool sign-in has this code."
  end
end
