ActiveAdmin.register_page "Sync Runner" do
  menu parent: "WarpEngine", priority: 11, label: "Sync Runner"

  content title: "Sync Runner" do
    form = WarpEngine::SyncRunnerForm.new(params)
    plan = nil
    error = nil
    if params[:preview].present?
      begin
        plan = WarpEngine::SyncService.new.plan(form.criteria)
      rescue ArgumentError => e
        error = e.message
      end
    end
    render "warp_engine/admin/sync_runner", form: form, plan: plan, error: error
  end

  page_action :run, method: :post do
    form = WarpEngine::SyncRunnerForm.new(params)
    return redirect_to admin_sync_runner_path(form.to_params.merge(preview: 1)) if params[:preview].present?

    result = WarpEngine::SyncService.new.run(form.criteria, servers: form.servers)
    if result.servers.empty?
      redirect_to admin_sync_runner_path(form.to_params), alert: "Choose at least one active sync server."
    else
      redirect_to admin_sync_runner_path(form.to_params),
                  notice: "#{result.queued} push(es) queued: #{result.releases.size} release(s) to " \
                          "#{result.servers.map(&:label).join(', ')}. Follow them under Sync Events."
    end
  rescue WarpEngine::SyncService::DisabledError, ArgumentError => e
    redirect_to admin_sync_runner_path(form&.to_params || {}), alert: e.message
  end
end
