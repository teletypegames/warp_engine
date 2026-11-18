module SyncHelpers
  def self.included(base)
    base.after { WarpEngine.config.sync = nil }
  end

  def sync_config(**settings)
    WarpEngine::Sync::Configuration.new.tap do |config|
      config.enabled = true
      settings.each { |name, value| config.public_send(:"#{name}=", value) }
      WarpEngine.config.sync = config
    end
  end
end
