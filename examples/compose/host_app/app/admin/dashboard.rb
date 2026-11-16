ActiveAdmin.register_page "Dashboard" do
  menu false

  controller do
    def index
      redirect_to admin_root_path
    end
  end
end
