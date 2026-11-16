Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  apipie

  root to: redirect("/admin")

  namespace :api do
    get "image/:id", to: "images#show"
  end

  mount WarpEngine::Engine => "/"
end
