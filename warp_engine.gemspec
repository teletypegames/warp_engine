require_relative "lib/warp_engine/version"

Gem::Specification.new do |spec|
  spec.name        = "warp_engine"
  spec.version     = WarpEngine::VERSION
  spec.authors     = [ "Teletype Games" ]
  spec.summary     = "Retro software catalog engine with a CI-callable release updater"
  spec.description = "Mountable Rails engine providing a software catalog (softwares, releases, " \
                     "release assets, images, platform links), a pipeline-callable update endpoint, " \
                     "a public read-only JSON API and ActiveAdmin resources for a host-owned admin."
  spec.license     = "MIT"
  spec.homepage    = "https://teletypegames.org"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://git.teletypegames.org"

  spec.files = Dir["{app,config,db,lib}/**/*", "README.md"]

  spec.add_dependency "rails", ">= 8.0"
end
