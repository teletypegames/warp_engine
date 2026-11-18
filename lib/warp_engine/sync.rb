require "warp_engine/sync/direction"
require "warp_engine/sync/configuration"
require "warp_engine/sync/filter"
require "warp_engine/sync/criteria"
require "warp_engine/sync/secret_box"
require "warp_engine/sync/package"
require "warp_engine/sync/transport"
require "warp_engine/sync/transports"
require "warp_engine/sync/transports/http"
require "warp_engine/sync/transports/rsync"

module WarpEngine
  # Copies releases between WarpEngines and to other places. Each partner is a
  # WarpEngine::SyncPeer, and sync runs in two directions, each with its own
  # settings in the <tt>sync</tt> block (WarpEngine::Sync::Configuration):
  #
  # [outbound] after every publish that did not itself come by sync,
  #            WarpEngine::SyncService hands the release to every peer that
  #            takes outbound pushes, through the peer's
  #            WarpEngine::Sync::Transport (+http+: the other engine's
  #            <tt>/build</tt> endpoints)
  # [inbound]  another engine pushes here with the +sync+ token this engine
  #            issued to its peer record; the <tt>/build</tt> endpoints check
  #            the inbound settings and mark the release's +origin+
  #
  #   WarpEngine.configure do
  #     sync do
  #       outbound do
  #         enabled true
  #         allowed_platforms %w[c64]
  #       end
  #       inbound do
  #         enabled true
  #       end
  #     end
  #   end
  module Sync
    # Where a published release came from: the CI (or a person) or another
    # engine by sync. Only a +ci+ release is pushed on.
    SOURCES = %i[ci sync].freeze

    module_function

    # Returns the WarpEngine::Sync::Configuration (WarpEngine::Configuration#sync).
    def config = WarpEngine.config.sync

    # Returns +true+ when this engine pushes to its peers.
    def outbound? = config.outbound.enabled?

    # Returns +true+ when this engine accepts pushes from its peers.
    def inbound? = config.inbound.enabled?
  end
end
