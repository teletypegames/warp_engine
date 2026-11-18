REGISTRY = ENV.fetch("WARP_REGISTRY", "git.teletypegames.org/build")
TOOLING_HOST = ENV.fetch("WARP_TOOLING_HOST", "https://git.teletypegames.org")
IMAGES = ENV.fetch("WARP_IMAGES", "2026.11.18")

TOOLS_IMAGE = "#{REGISTRY}/ci-tools@sha256:8bb7d77188d3d48ac8c2b1aeea3476f39f41f270e90bdc64ba7b4a35e8037519".freeze
COMMODORE_PLAYER = "#{REGISTRY}/commodore-player:#{IMAGES}".freeze

BUILDERS = {
  godot:      "#{REGISTRY}/godot-builder:#{IMAGES}",
  phaser:     "#{REGISTRY}/phaser-builder:#{IMAGES}",
  love:       "#{REGISTRY}/love-builder:#{IMAGES}",
  bevy:       "#{REGISTRY}/bevy-builder:#{IMAGES}",
  c64:        "#{REGISTRY}/c64-builder:#{IMAGES}",
  plus4:      "#{REGISTRY}/plus4-builder:#{IMAGES}",
  ebitengine: "#{REGISTRY}/ebitengine-builder:#{IMAGES}",
  tic80:      "#{REGISTRY}/tic80pro:#{IMAGES}",
  dos:        "#{REGISTRY}/dos-builder:#{IMAGES}",
  electron:   "#{REGISTRY}/electron-builder:#{IMAGES}"
}.freeze

WEB_SHELLS = {
  phaser:     "#{TOOLING_HOST}/build/phaser-tools/raw/branch/master/web/index.html",
  bevy:       "#{TOOLING_HOST}/tools/bevy-tools/raw/branch/master/web/index.html",
  ebitengine: "#{TOOLING_HOST}/tools/ebitengine-tools/raw/branch/master/web/index.html"
}.freeze

TOOLING = {
  tic80:      { template: "build/tic80-tools" },
  ebitengine: { template: "build/ebitengine-tools", demo: "demos/ebitengine-demo" },
  love:       { template: "build/love-tools",       demo: "demos/love-demo" },
  c64:        { template: "build/c64-tools" },
  plus4:      { template: "build/plus4-build",      demo: "demos/plus4-demo" },
  godot:      { template: "build/godot-tools",      demo: "demos/pong" },
  bevy:       { template: "build/bevy-tools",       demo: "demos/bevy-demo" },
  phaser:     { template: "build/phaser-tools",     demo: "demos/phaser-demo" },
  dos:        { template: "build/dos-tools" },
  electron:   { template: "build/electron-tools",   demo: "stores/warp-engine-client" }
}.freeze

Rails.application.config.to_prepare do
  WarpEngine.configure do
    site_url ENV.fetch("SITE_URL", "http://localhost:8080")
    store_name ENV.fetch("STORE_NAME", "My Studio")
    file_container_path ENV.fetch("FILE_CONTAINER_PATH", "/softwares")
    update_secret ENV["UPDATE_SECRET"]
    application_tokens from: :database, owner: "AdminUser"
    image_class "Image"

    runtime :emulatorjs, version: "4.2.3"

    forge :gitea, url: ENV["GITEA_URL"], token: ENV["GITEA_API_TOKEN"], owner: ENV.fetch("GITEA_OWNER", "games")
    TOOLING.each do |platform, repos|
      platform_tooling platform, **repos.transform_values { |path| "#{TOOLING_HOST}/#{path}" }, ref: "master"
    end

    admin_api do
      enable
      public_openapi
    end

    ci :woodpecker do
      url            ENV["WOODPECKER_URL"]
      api_token      ENV["WOODPECKER_API_TOKEN"]
      repo_owner     ENV.fetch("GITEA_OWNER", "games")
      public_key_url ENV["WOODPECKER_PUBLIC_KEY_URL"]
      update_server  ENV.fetch("UPDATE_SERVER", "http://app:3000")
      tools          TOOLS_IMAGE

      platform :godot,      builder: BUILDERS[:godot]
      platform :phaser,     builder: BUILDERS[:phaser],     web_shell: WEB_SHELLS[:phaser]
      platform :love,       builder: BUILDERS[:love],       bundle_id_prefix: ENV.fetch("BUNDLE_ID_PREFIX", "org.example")
      platform :bevy,       builder: BUILDERS[:bevy],       web_shell: WEB_SHELLS[:bevy]
      platform :c64,        builder: BUILDERS[:c64],        exporter: COMMODORE_PLAYER
      platform :plus4,      builder: BUILDERS[:plus4],      exporter: COMMODORE_PLAYER
      platform :ebitengine, builder: BUILDERS[:ebitengine], web_shell: WEB_SHELLS[:ebitengine]
      platform :tic80,      builder: BUILDERS[:tic80]
      platform :dos,        builder: BUILDERS[:dos],        forge_release: true
      platform :electron,   builder: BUILDERS[:electron]
    end
  end
end
