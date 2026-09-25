ActiveAdmin.register_page "Files" do
  menu parent: "🌀 WarpEngine", priority: 6, label: "📁 Files"

  content do
    service = WarpEngine::FileManagerService.new
    current_dir = params[:dir].to_s.presence || ""
    picker_mode = params[:picker].present?
    picker_field = params[:field].to_s

    begin
      entries = service.list(current_dir, with_download_counts: true)
    rescue ArgumentError
      entries = []
    end

    if picker_mode
      text_node "<style>#header,#tabs,.footer,#title_bar,#utility_nav{display:none!important}#active_admin_content{margin:0;padding:0}#wrapper{margin:0}body{min-height:auto}</style>".html_safe
    end

    div class: "file-manager" do
      h2 do
        text_node "File Manager"
        if picker_mode
          span " — select a file or folder", style: "font-size:14px; color:#888; font-weight:normal;"
        end
      end

      div class: "fm-breadcrumbs" do
        parts = current_dir.split("/").reject(&:blank?)
        picker_params = picker_mode ? { picker: 1, field: picker_field } : {}

        a "softwares/", href: admin_files_path(picker_params)
        accumulated = ""
        parts.each do |part|
          accumulated = [ accumulated, part ].reject(&:blank?).join("/")
          a "#{part}/", href: admin_files_path(picker_params.merge(dir: accumulated))
        end
      end

      div class: "fm-actions fm-dropzone", id: "fm-page-dropzone" do
        form action: admin_files_upload_path, method: "post", enctype: "multipart/form-data", class: "fm-inline-form" do |_f|
          input type: "hidden", name: "authenticity_token", value: form_authenticity_token
          input type: "hidden", name: "dir", value: current_dir
          input type: "file", name: "file", required: true
          input type: "submit", value: "Upload", class: "fm-btn"
        end

        form action: admin_files_mkdir_path, method: "post", class: "fm-inline-form" do |_f|
          input type: "hidden", name: "authenticity_token", value: form_authenticity_token
          input type: "hidden", name: "dir", value: current_dir
          input type: "text", name: "name", placeholder: "New folder name", required: true, class: "fm-text-input"
          input type: "submit", value: "Create Folder", class: "fm-btn"
        end
      end

      table class: "fm-table" do
        thead do
          tr do
            th "Name"
            th "Size", style: "width:100px"
            th "DL", style: "width:50px"
            th "Modified", style: "width:160px"
            th "", style: "width:#{picker_mode ? '160' : '120'}px"
          end
        end

        tbody do
          if current_dir.present?
            parent = File.dirname(current_dir)
            parent = "" if parent == "."
            picker_params = picker_mode ? { picker: 1, field: picker_field } : {}

            tr do
              td do
                span "#{WarpEngine::FileIcon::DIRECTORY} ", style: "font-size:15px;"
                a "..", href: admin_files_path(picker_params.merge(dir: parent))
              end
              td ""
              td ""
              td ""
              td ""
            end
          end

          entries.each do |entry|
            tr do
              td do
                picker_params = picker_mode ? { picker: 1, field: picker_field } : {}
                if entry[:type] == :directory
                  span "#{WarpEngine::FileIcon::DIRECTORY} ", style: "font-size:15px;"
                  a entry[:name], href: admin_files_path(picker_params.merge(dir: entry[:path]))
                else
                  span "#{WarpEngine::FileIcon.for(entry[:name])} ", style: "font-size:15px;"
                  span entry[:name]
                end
              end
              td do
                text_node(entry[:size] ? number_to_human_size(entry[:size]) : "")
              end
              td do
                if entry[:type] != :directory
                  count = entry[:downloads] || 0
                  span count.to_s, style: count > 0 ? "font-weight:bold;" : "color:#999;"
                end
              end
              td do
                text_node(entry[:mtime]&.strftime("%Y-%m-%d %H:%M") || "")
              end
              td class: "fm-entry-actions" do
                entry_id = entry[:path].parameterize

                if entry[:type] != :directory
                  a "⬇️", href: "/file/#{entry[:path]}", class: "fm-icon-btn", title: "Download", download: entry[:name]
                end

                a "✏️", href: "#", class: "fm-icon-btn", title: "Rename",
                  onclick: "var n=prompt('New name:','#{escape_javascript(entry[:name])}');if(n){var f=document.getElementById('rename-#{entry_id}');f.querySelector('[name=new_name]').value=n;f.submit();}return false;"

                a "🗑️", href: "#", class: "fm-icon-btn fm-icon-danger", title: "Delete",
                  onclick: "if(confirm('Delete \\'#{escape_javascript(entry[:name])}\\'?')){document.getElementById('delete-#{entry_id}').submit();}return false;"

                if entry[:type] != :directory
                  a "📊", href: admin_downloads_path(q: { file_path_cont: entry[:path] }), class: "fm-icon-btn", title: "Stats"
                end

                if picker_mode
                  abs_path = File.join(WarpEngine.config.file_container_path, entry[:path])
                  a "Select", href: "#", class: "fm-btn fm-btn-select",
                    onclick: "var inp=window.parent.document.getElementById('#{escape_javascript(picker_field)}');if(inp){inp.value='#{escape_javascript(abs_path)}';}var ov=window.parent.document.querySelector('.fm-modal-overlay');if(ov){ov.remove();window.parent.document.body.style.overflow='';}return false;"
                end

                form action: admin_files_rename_path, method: "post", id: "rename-#{entry_id}", style: "display:none" do
                  input type: "hidden", name: "authenticity_token", value: form_authenticity_token
                  input type: "hidden", name: "path", value: entry[:path]
                  input type: "hidden", name: "new_name", value: ""
                  input type: "hidden", name: "dir", value: current_dir
                end

                form action: admin_files_delete_path, method: "post", id: "delete-#{entry_id}", style: "display:none" do
                  input type: "hidden", name: "authenticity_token", value: form_authenticity_token
                  input type: "hidden", name: "_method", value: "delete"
                  input type: "hidden", name: "path", value: entry[:path]
                  input type: "hidden", name: "dir", value: current_dir
                end
              end
            end
          end
        end
      end

      if entries.empty? && current_dir.blank?
        para "No files found in /softwares", style: "color:#999; text-align:center; padding:40px 0;"
      end
    end
  end

  page_action :list, method: :get do
    service = WarpEngine::FileManagerService.new
    dir = params[:dir].to_s.presence || ""
    begin
      entries = service.list(dir)
      render json: { entries: entries, dir: dir }
    rescue ArgumentError => e
      render json: { entries: [], dir: dir, error: e.message }
    end
  end

  page_action :ajax_upload, method: :post do
    service = WarpEngine::FileManagerService.new
    path = service.upload(params[:dir].to_s, params[:file])
    render json: { ok: true, path: path }
  rescue => e
    render json: { ok: false, error: e.message }, status: 422
  end

  page_action :upload, method: :post do
    WarpEngine::FileManagerService.new.upload(params[:dir].to_s, params[:file])
    redirect_to_files notice: "File uploaded."
  rescue => e
    redirect_to_files alert: "Upload failed: #{e.message}"
  end

  page_action :mkdir, method: :post do
    WarpEngine::FileManagerService.new.mkdir(params[:dir].to_s, params[:name].to_s)
    redirect_to_files notice: "Folder created."
  rescue => e
    redirect_to_files alert: "Failed: #{e.message}"
  end

  page_action :rename, method: :post do
    WarpEngine::FileManagerService.new.rename(params[:path].to_s, params[:new_name].to_s)
    redirect_to_files notice: "Renamed."
  rescue => e
    redirect_to_files alert: "Rename failed: #{e.message}"
  end

  page_action :delete, method: :delete do
    WarpEngine::FileManagerService.new.delete(params[:path].to_s)
    redirect_to_files dir: params[:dir].presence || parent_dir_of(params[:path]), notice: "Deleted."
  rescue => e
    redirect_to_files alert: "Delete failed: #{e.message}"
  end

  controller do
    private

    def redirect_to_files(dir: nil, notice: nil, alert: nil)
      target = admin_files_path(dir: dir || params[:dir], picker: params[:picker], field: params[:field])
      redirect_to target, notice: notice, alert: alert
    end

    def parent_dir_of(path)
      parent = File.dirname(path.to_s)
      parent == "." ? "" : parent
    end
  end
end
