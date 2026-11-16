Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  config.action_mailer.default_url_options = { host: "localhost", port: ENV.fetch("APP_PORT", "8080") }

  config.assets.debug = true

  config.logger = ActiveSupport::Logger.new($stdout)
end
