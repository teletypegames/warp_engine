WarpEngine::Engine.routes.draw do
  namespace :api do
    get "software",               to: "software#index"
    get "software/highlighted",   to: "software_highlighted#index"
    get "image/:id",              to: "images#show"
    get "download",               to: "downloads#show"
    get "builds",                 to: "builds#index"
    get "softwares/:name/builds", to: "software_builds#show"

    get  "ci/pipelines",             to: "ci#pipelines"
    get  "ci/pipelines/:id/status",  to: "ci#status"
    post "ci/pipelines/:id/trigger", to: "ci#trigger"
  end

  post "build/upload",  to: "build/uploads#create"
  post "build/publish", to: "build/publish#create"
  get  "build/config",  to: "build/configs#show"
  post "build/config",  to: "build/configs#create"

  get "file/*path", to: "files#show", format: false
end
