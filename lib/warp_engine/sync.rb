require "warp_engine/sync/configuration"
require "warp_engine/sync/filter"
require "warp_engine/sync/criteria"
require "warp_engine/sync/secret_box"
require "warp_engine/sync/client"

module WarpEngine
  # Copies the releases of this engine to other WarpEngines (the
  # WarpEngine::SyncServer records), the way a CI would: after every publish
  # that did not itself come by sync, WarpEngine::SyncService sends the
  # uploaded files to <tt>POST /build/upload</tt> and asks for
  # <tt>POST /build/publish</tt> on each server, with a token the other side
  # gave the +sync+ scope. The receiving side needs nothing but that token.
  #
  #   WarpEngine.configure do
  #     sync do
  #       enabled true
  #       software_switch :opt_out
  #       denied_softwares %w[*-test]
  #       allowed_platforms %w[c64 plus4]
  #     end
  #   end
  module Sync
    # A sync server did not answer: refused, timed out, broken TLS. The push
    # is tried again.
    class ConnectionError < WarpEngine::Error; end

    # Where a published release came from: the CI (or a person), or another
    # engine by sync. Only a +CI+ release is pushed on.
    SOURCES = %i[ci sync].freeze

    module_function

    # Returns the WarpEngine::Sync::Configuration (WarpEngine::Configuration#sync).
    def config = WarpEngine.config.sync

    # Returns +true+ when sync is enabled.
    def enabled? = config.enabled?
  end
end
