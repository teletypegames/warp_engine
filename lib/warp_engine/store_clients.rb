module WarpEngine
  # The store engines a WarpEngine serves to the machines they run on: each
  # one is a catalog software (a +batocera+ or +retroarch+ platform release)
  # whose installer and store config the engine renders for its own catalog
  # (WarpEngine::StoreClientService, <tt>/api/stores/CLIENT/*</tt>). What a
  # host changes about one is a WarpEngine::StoreClient record.
  module StoreClients
    # One store engine: its +key+ (also the platform it is released on), the
    # +label+ of the machine, the catalog +software+ it is released as by
    # default, and the +template+ its store config starts from.
    Client = ::Data.define(:key, :label, :software, :template) do
      # Returns the store config template as a fresh Hash.
      def config_template = JSON.parse(File.read(template))
    end

    # The store engines, by key.
    ALL = {
      "batocera"  => Client.new(key: "batocera", label: "Batocera", software: "we-batocera",
                                template: File.expand_path("store_clients/batocera.json", __dir__)),
      "retroarch" => Client.new(key: "retroarch", label: "RetroArch", software: "we-retroarch",
                                template: File.expand_path("store_clients/retroarch.json", __dir__))
    }.freeze

    module_function

    # Returns the keys of the store engines.
    def keys = ALL.keys

    # Returns the Client named +key+, or +nil+.
    def find(key) = ALL[key.to_s]

    # Returns the platform names any store engine's config template carries.
    def platforms
      @platforms ||= ALL.values.flat_map { |client| client.config_template.fetch("platforms", {}).keys }.uniq.freeze
    end
  end
end
