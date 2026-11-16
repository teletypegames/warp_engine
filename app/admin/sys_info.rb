ActiveAdmin.register_page "SysInfo" do
  menu parent: "WarpEngine", priority: 20, label: "SysInfo"

  content title: "SysInfo" do
    render "warp_engine/admin/sys_info", sys_info: WarpEngine::SysInfo.new(live: params[:live] != "0")
  end
end
