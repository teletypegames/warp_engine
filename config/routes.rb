WarpEngine::Engine.routes.draw do
  namespace :api do
    get "software",               to: "software#index"
    get "software/highlighted",   to: "software_highlighted#index"
    get "image/:id",              to: "images#show"
    get "download",               to: "downloads#show"
    get "builds",                 to: "builds#index"
    get "softwares/:name/builds", to: "software_builds#show"
  end

  get "update",     to: "update#update"
  get "file/*path", to: "files#show", format: false
end
