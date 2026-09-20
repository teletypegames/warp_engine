WarpEngine::Engine.routes.draw do
  namespace :api do
    get "service", to: "service#show"

    namespace :auth do
      post   "device",       to: "devices#create"
      post   "device/token", to: "device_tokens#create"
      delete "token",        to: "tokens#destroy"
    end

    get "software",               to: "software#index"
    get "software/highlighted",   to: "software_highlighted#show"
    get "software/facets",        to: "software_facets#show"
    get "software/vocabulary",    to: "software_vocabulary#show"
    get "download",               to: "downloads#show"
    get "builds",                 to: "builds#index"
    get "softwares/:name/builds", to: "software_builds#show"

    get  "ci/pipelines",             to: "ci/pipelines#index"
    get  "ci/pipelines/:id/status",  to: "ci/pipelines#show"
    post "ci/pipelines/:id/trigger", to: "ci/pipeline_runs#create"
  end

  post "build/upload",  to: "build/uploads#create"
  post "build/publish", to: "build/publish#create"
  get  "build/config",  to: "build/configs#show"
  post "build/config",  to: "build/configs#create"

  get "file/*path", to: "files#show", format: false
end
