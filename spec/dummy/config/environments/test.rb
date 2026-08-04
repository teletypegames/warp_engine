Rails.application.configure do
  config.cache_classes = true
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  config.log_level = :warn
end
