require "json"
require "uri"
require "rails/generators"

module WarpEngine
  module Generators
    # <tt>rails g warp_engine:store batocera|retroarch</tt>: writes the store
    # config and a short installer for one of the WarpEngine store engines into
    # the host's +public/stores/CLIENT/+, so a Batocera box or a RetroArch
    # install reads this host's catalog:
    #
    #   bin/rails g warp_engine:store batocera --base-url http://192.168.1.20:8080 --name "My Studio"
    #   curl -fsSL http://192.168.1.20:8080/stores/batocera/install.sh | sh   # on the box
    #
    # The config starts from the one teletypegames.org runs, keeps the
    # platforms this host has, and is the host's own file from then on. The
    # installer pins the store engine and warpstore to the commits that config
    # was tested with.
    class StoreGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      # The store engines this generator knows: label, repository and the
      # commits of the engine and of warpstore the installer pins.
      CLIENTS = {
        "batocera" => { label: "Batocera", repo: "warp-engine-batocera-store",
                        engine: "8ffe70d8d0eea50ccc1a56ea54665089fbf58761",
                        warpstore: "168624695532a8db0977e0dd295890afc08cccc9" },
        "retroarch" => { label: "RetroArch", repo: "warp-engine-retroarch-store",
                         engine: "b142f935e454673471af089aed50f62a81c35f19",
                         warpstore: "386897588d078126aa07ccd8327cf00b48309961" }
      }.freeze

      # Where the store engines and warpstore are fetched from.
      FORGE = "https://git.teletypegames.org".freeze

      argument :client, type: :string, desc: "batocera or retroarch"

      class_option :base_url, type: :string, desc: "The catalog address the box reaches (default: the site_url setting)"
      class_option :name, type: :string, desc: "The store's name on the box (default: the catalog host)"
      class_option :id, type: :string, desc: "The store id and folder name (default: from the catalog host)"
      class_option :statuses, type: :array, desc: "The statuses the store installs (default: the ones shown by default)"

      # Checks the client and the catalog address. Raises Thor::Error when the
      # client is unknown or no address is given or configured.
      def check
        raise Thor::Error, "#{client} is not a store engine: #{CLIENTS.keys.join(' or ')}" unless CLIENTS.key?(client)
        raise Thor::Error, "no catalog address: pass --base-url or set site_url" if base_url.blank?
      end

      # Writes <tt>public/stores/CLIENT/config.json</tt>.
      def write_config
        create_file "public/stores/#{client}/config.json", "#{JSON.pretty_generate(config)}\n"
      end

      # Writes <tt>public/stores/CLIENT/install.sh</tt>.
      def write_installer
        @store_name = store_name
        template "install.sh.tt", "public/stores/#{client}/install.sh"
        chmod "public/stores/#{client}/install.sh", 0o755
      end

      # Prints how to install the store on the box.
      def show_next_steps
        say <<~MSG

          #{client_label} store "#{store_name}" (#{config['platforms'].keys.join(', ')}). On the box:

            curl -fsSL #{public_url('install.sh')} | sh

          The box must reach #{base_url}; edit public/stores/#{client}/config.json to change what it installs.
        MSG
      end

      private

      def client_label = CLIENTS.fetch(client)[:label]

      def base_url = (options[:base_url].presence || WarpEngine.config.site_url.to_s).chomp("/")

      def host = URI(base_url).host.to_s

      def store_name = options[:name].presence || host

      def store_id
        (options[:id].presence || host.split(".").reject { |part| %w[www].include?(part) }.first.to_s)
          .downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-").presence || "store"
      end

      def statuses
        options[:statuses].presence || WarpEngine::SoftwareStatus.default_visible_keys
      end

      def public_url(file) = "#{base_url}/stores/#{client}/#{file}"

      def engine_raw_base
        spec = CLIENTS.fetch(client)
        "#{FORGE}/stores/#{spec[:repo]}/raw/commit/#{spec[:engine]}"
      end

      def warpstore_raw_base = "#{FORGE}/engines/warpstore/raw/commit/#{CLIENTS.fetch(client)[:warpstore]}"

      def config
        @config ||= JSON.parse(File.read(File.join(self.class.source_root, "#{client}.json"))).tap do |config|
          config["store"].merge!("id" => store_id, "name" => store_name, "base_url" => base_url)
          config["paths"]["subfolder"] = store_id
          config["emulationstation"]["folder_name"] = store_name if config.key?("emulationstation")
          config["catalog"]["statuses"] = statuses
          config["platforms"].select! { |name, _| WarpEngine::Platform.exists?(name) }
        end
      end
    end
  end
end
