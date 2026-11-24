module WarpEngine
  # Model concern that tells the rest of the engine when a release or a
  # software is soft-deleted: after WarpEngine::SoftDeletable#soft_delete! it
  # instruments <tt>warp_engine.remove</tt> with the +record+, which sync
  # (WarpEngine::SyncService#dispatch_removal) passes on to the peers.
  module RemovalNotifying
    # Soft-deletes the record, then instruments <tt>warp_engine.remove</tt>.
    # Returns what the soft delete returned.
    def soft_delete!
      super.tap { ActiveSupport::Notifications.instrument("warp_engine.remove", record: self) }
    end
  end
end
