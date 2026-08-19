WarpEngine::Engine.routes.draw do
  namespace :api do
    # What this deployment is and what it can do. A client reads it before it can have
    # a credential, so it is public and cheap.
    get "service", to: "service#show"

    # Device sign-in, for clients that have no browser of their own (RFC 8628).
    # Inactive — 404 on every action — unless the host configured a subject class.
    namespace :auth do
      post   "device",       to: "devices#create"
      post   "device/token", to: "devices#token"
      delete "token",        to: "tokens#destroy"
    end

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
