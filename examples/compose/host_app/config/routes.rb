Rails.application.routes.draw do
  apipie

  namespace :api do
    get "image/:id", to: "images#show"
  end

  mount WarpEngine::Engine => "/"
end
