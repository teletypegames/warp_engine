WarpEngine::Engine.routes.draw do
  get ".well-known/warp-engine", to: "well_known#show", format: false

  WarpEngine::Outlets.draw_routes(self)

  namespace :api do
    get "builds",                 to: "builds#index"
    get "softwares/:name/builds", to: "software_builds#show"

    get  "ci/pipelines",             to: "ci/pipelines#index"
    get  "ci/pipelines/:id/status",  to: "ci/pipelines#show"
    post "ci/pipelines/:id/trigger", to: "ci/pipeline_runs#create"
  end

  post "build/upload",  to: "build/uploads#create"
  post "build/publish", to: "build/publish#create"
  post "build/images",  to: "build/images#create"
  post "build/images/upload", to: "build/images#upload"
  delete "build/release", to: "build/removals#destroy"
  post "build/runtime", to: "build/runtimes#create"
  get  "build/config",  to: "build/configs#show"
  post "build/config",  to: "build/configs#create"
  post "build/check",  to: "build/checks#create"
  get  "build/platforms",                       to: "build/platforms#index"
  get  "build/platforms/:name",                 to: "build/platforms#show"
  get  "build/platforms/:name/metadata-schema", to: "build/platforms#metadata_schema"

  scope WarpEngine::AdminApi.url_path, module: "api/admin", as: "api_admin", format: false do
    get  "openapi.json", to: "documents#openapi", defaults: { format: "json" }, as: :openapi
    get  "openapi.yaml", to: "documents#openapi", defaults: { format: "yaml" }, as: :openapi_yaml
    get  "docs",         to: "documents#docs", as: :docs
    post "mcp",          to: "mcp#create", as: :mcp
    match "mcp",         to: "mcp#method_not_allowed", via: %i[get delete]

    WarpEngine::AdminApi::Registry.operations.each do |operation|
      constraints = operation.path_param_names.grep(/id\z/i).to_h { |name| [ name.to_sym, /\d+/ ] }
      match operation.path, to: "operations#execute", via: operation.verb,
                            defaults: { operation: operation.key }, constraints: constraints
    end
  end
end
