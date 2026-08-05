Rails.application.routes.draw do
  apipie

  # Keep the engine mount the last entry so the host's own routes win.
  mount WarpEngine::Engine => "/"
end
