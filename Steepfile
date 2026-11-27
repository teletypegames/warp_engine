D = Steep::Diagnostic

target :seams do
  signature "sig", "steep/stubs"

  check "lib/warp_engine/access.rb",
        "lib/warp_engine/storage.rb",
        "lib/warp_engine/access_policy.rb",
        "lib/warp_engine/images.rb",
        "lib/warp_engine/ci.rb",
        "lib/warp_engine/scm.rb",
        "lib/warp_engine/store_registry.rb",
        "lib/warp_engine/sync/transport.rb",
        "lib/warp_engine/feeds/base.rb"

  library "uri", "pathname"

  configure_code_diagnostics(D::Ruby.default)
end
