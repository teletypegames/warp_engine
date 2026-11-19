module WarpEngine
  # What happens to a WarpEngine::SyncPeer beyond a save: pairing one with
  # its token in one step (#pair), removing one with its token (#remove) and
  # queuing the pushes to one (#queue_push). The ActiveAdmin page and the
  # Admin API go through it.
  class SyncPeerService
    # The outcome of #pair: the saved +peer+ and the +token+ just issued,
    # whose +plain_token+ is shown once.
    Paired = ::Data.define(:peer, :token)

    # Adds an inbound-only +http+ peer labelled +label+ for +owner+ (who
    # paired it, WarpEngine::SyncPeer#created_by) and issues its inbound
    # token, in one transaction. Returns a Paired. Raises
    # ActiveRecord::RecordInvalid when the peer does not save.
    def pair(label:, owner:)
      peer = SyncPeer.new(label: label, transport: "http", inbound_enabled: true, outbound_enabled: false, created_by: owner)
      SyncPeer.transaction do
        peer.save!
        Paired.new(peer: peer, token: peer.issue_inbound_token!)
      end
    end

    # Revokes the inbound token of +peer+ and soft-deletes it. Returns the peer.
    def remove(peer)
      SyncPeer.transaction do
        peer.inbound_token&.revoke!
        peer.soft_delete!
      end
      peer
    end

    # Queues a WarpEngine::SyncBackfillJob for +peer+: the newest allowed
    # release of every software, or every allowed one with +all+.
    def queue_push(peer, all: false)
      SyncBackfillJob.perform_later(peer.id, nil, all)
    end
  end
end
