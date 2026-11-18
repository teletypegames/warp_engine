module SyncHelpers
  def self.included(base)
    base.after { WarpEngine.config.sync = nil }
  end

  def sync_config(events: true, inbound: {}, **outbound)
    WarpEngine::Sync::Configuration.new.tap do |config|
      config.events = events
      config.outbound.enabled = true
      outbound.each { |name, value| config.outbound.public_send(:"#{name}=", value) }
      inbound.each { |name, value| config.inbound.public_send(:"#{name}=", value) }
      WarpEngine.config.sync = config
    end
  end

  def sync_peer(label: "Other", host: "https://other.example/warp", secret: "other-token", **attributes)
    WarpEngine::SyncPeer.create!(label: label, transport: "http", transport_options: { "host" => host }, secret: secret,
                                 outbound_enabled: true, **attributes)
  end
end
