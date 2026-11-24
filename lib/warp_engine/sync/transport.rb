module WarpEngine
  module Sync
    # How a WarpEngine::Sync::Package gets to a WarpEngine::SyncPeer: the base
    # of the transports (WarpEngine::Sync::Transports). The engine ships
    # +http+ (WarpEngine::Sync::Transports::Http, another WarpEngine's
    # <tt>/build</tt> endpoints) and +rsync+ (WarpEngine::Sync::Transports::Rsync,
    # a file mirror over SSH); a host registers its own with
    # <tt>register_sync_transport</tt>.
    #
    # A transport class names itself (+key+, +label+), describes its settings
    # (+options+: the admin draws the peer form from them) and says whether
    # the other side is a catalog that publishes (+publishes?+). An instance
    # works for one peer: #check, #existing, #deliver and, when it carries
    # images (+images?+), #deliver_images.
    class Transport
      # The other side did not answer (refused, timed out, broken TLS): the
      # push is tried again.
      class Unreachable < WarpEngine::Error; end

      # One setting of a transport: its +name+ (the key in the peer's
      # +transport_options+), a +label+, its +type+ (+:string+, +:text+ for
      # several lines, +:boolean+), whether it is +required+ for an outbound peer, whether it
      # is the +secret+ (stored encrypted in the peer's +secret+) and a +hint+.
      Option = ::Data.define(:name, :label, :type, :required, :secret, :hint)

      # What #check found: whether the other side takes us (+ok+), a +status+
      # code (HTTP or exit status, or +nil+), its WarpEngine +version+ when it
      # tells (or +nil+) and a +message+ for a person.
      CheckResult = ::Data.define(:ok, :status, :version, :message)

      # What #deliver did: +status+ (+succeeded+, +skipped+ or +failed+, as a
      # WarpEngine::SyncEvent), the other side's +code+ (or +nil+) and a
      # +message+ (+nil+ when it went through).
      Delivery = ::Data.define(:status, :code, :message)

      class << self
        # Returns the transport's key, the value of a peer's +transport+.
        def key = raise(NotImplementedError, "#{name} must define self.key")

        # Returns the human name, by default the titleized key.
        def label = key.to_s.titleize

        # Returns the Option list, by default none.
        def options = []

        # Returns +true+ when the other side is a catalog that publishes the
        # release (a WarpEngine), +false+ for a file mirror.
        def publishes? = false

        # Returns +true+ when the transport sends a software's images too
        # (#deliver_images), by default +false+.
        def images? = false

        # Returns the error messages of +peer+'s options for this transport:
        # a required option missing on an outbound peer.
        def errors_for(peer)
          return [] unless peer.outbound_enabled

          options.select(&:required).filter_map do |option|
            value = option.secret ? peer.secret : peer.option(option.name)
            "#{option.label} is required" if value.blank?
          end
        end
      end

      # The WarpEngine::SyncPeer this instance works for.
      attr_reader :peer

      # [peer] the WarpEngine::SyncPeer
      def initialize(peer)
        @peer = peer
      end

      # Checks that the other side answers and takes our credentials, without
      # changing anything there. Returns a CheckResult.
      def check = raise(NotImplementedError, "#{self.class.name} must define #check")

      # Returns the asset kinds the other side has of +package+'s version, or
      # +nil+ when it cannot tell (then nothing is skipped as existing).
      def existing(_package) = nil

      # Sends +package+, yielding each step's name (<tt>upload:<file></tt>,
      # +publish+) before it runs. Returns a Delivery. Raises Unreachable when
      # the other side does not answer.
      def deliver(_package) = raise(NotImplementedError, "#{self.class.name} must define #deliver")

      # Makes the gallery of the software +name+ on the other side what
      # +images+ (WarpEngine::Sync::ImageFile values, in order) say: sends
      # the ones it lacks, orders them, and drops the ones it got by sync
      # before and +images+ no longer has. Yields each step's name like
      # #deliver. Returns a Delivery, or +nil+ when the transport carries no
      # images (the default). Raises Unreachable.
      def deliver_images(_name, _images) = nil

      # Removes from the other side what this engine pushed there of the
      # software +name+: the release +version+, or every such release and
      # the software itself when +version+ is +nil+. Returns a Delivery, or
      # +nil+ when the transport carries no removals (the default). Raises
      # Unreachable.
      def deliver_removal(_name, _version) = nil

      private

      def option(name) = peer.option(name)

      def secret = peer.secret
    end
  end
end
