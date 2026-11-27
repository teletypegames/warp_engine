require "warp_engine/runtime/controls"

module WarpEngine
  class Platform
    # How a platform's releases play on the web in one runtime: the binding
    # of a platform to a WarpEngine::Runtime. A platform may have several (one
    # of them the default) and a runtime may serve several platforms.
    #
    # [key]      the binding's name on the platform, unique there (default: the runtime name)
    # [runtime]  the runtime name
    # [payload]  the asset kind the runtime plays (default +package+)
    # [params]   the runtime parameters (a frozen Hash with Symbol keys)
    # [default]  the binding a release uses when its metadata names none
    # [enabled]  +false+ when the host switched it off
    # [isolated] the page needs cross-origin isolation (+SharedArrayBuffer+,
    #            a threaded core): it is served with COOP/COEP headers
    # [controls] the controls help rows of the binding
    #            (WarpEngine::Runtime::Controls), after the ones the runtime
    #            generates
    WebBinding = ::Data.define(:key, :runtime, :payload, :params, :default, :enabled, :isolated, :controls) do
      # Builds a binding with the defaults: keyed by the runtime, playing the
      # package, enabled, not the default, not isolated, without controls help.
      def self.build(runtime, as: nil, payload: :package, default: false, enabled: true, isolated: false, controls: [],
                     **params)
        new(key: (as || runtime).to_s, runtime: runtime.to_s, payload: payload.to_s, params: params.freeze,
            default: default, enabled: enabled, isolated: isolated, controls: WarpEngine::Runtime::Controls.normalize(controls))
      end

      # Returns the WarpEngine::Runtime, or +nil+ when it is not defined.
      def runtime_object = WarpEngine::Runtime.find(runtime)

      # Returns the controls help of a release playing in the binding with
      # the resolved parameters +params+ (see
      # WarpEngine::Runtime::Definition#resolve_params): the rows the runtime
      # generates, then the binding's own. Only the binding's rows when the
      # runtime is not defined.
      def controls_for(params)
        generated = runtime_object&.definition&.controls_for(params) || []
        (generated + controls).freeze
      end

      # Returns the problems of the binding as messages: an unknown runtime or
      # payload kind, parameters the runtime does not take, malformed controls
      # rows. Empty when it is usable.
      def errors
        found = runtime_object
        return [ "runtime #{runtime} is not defined" ] if found.nil?

        problems = WarpEngine::AssetKinds::ALL.key?(WarpEngine::AssetKinds.canonical(payload)) ? [] : [ "payload #{payload} is not an asset kind" ]
        problems + found.definition.param_errors(params) + WarpEngine::Runtime::Controls.errors(controls)
      end

      # Returns +true+ when #errors is empty.
      def valid? = errors.empty?
    end
  end
end
