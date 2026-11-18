module WarpEngine
  module Sync
    # The registry of the sync transports (WarpEngine::Sync::Transport): the
    # builtin ones and those the host registered with
    # <tt>register_sync_transport</tt> (WarpEngine::Configuration#sync_transports).
    module Transports
      # The transports the engine ships, by key.
      BUILTIN = { "http"  => "WarpEngine::Sync::Transports::Http",
                  "rsync" => "WarpEngine::Sync::Transports::Rsync" }.freeze

      module_function

      # Returns every transport, key to class name.
      def all = BUILTIN.merge(WarpEngine.config.sync_transports.transform_keys(&:to_s))

      # Returns the keys of every transport.
      def keys = all.keys

      # Returns the transport class of +key+, or +nil+ when there is none or
      # its class does not load.
      def find(key)
        all[key.to_s]&.safe_constantize
      end

      # Returns the transport classes that load, in key order.
      def classes = keys.filter_map { |key| find(key) }

      # Returns a warning for each registered transport whose class does not load.
      def validate!
        all.filter_map { |key, class_name| "sync transport #{key}: #{class_name} does not load" if class_name.safe_constantize.nil? }
      end
    end
  end
end
