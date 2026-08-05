Apipie.configure do |config|
  config.app_name = "WarpEngine Example Host"
  config.api_base_url = ""
  config.doc_base_url = "/api/docs"
  config.api_controllers_matcher = [
    "#{WarpEngine::Engine.root}/app/controllers/**/*.rb"
  ]
  config.validate = false
  config.translate = false
  config.default_version = "1.0"
end
