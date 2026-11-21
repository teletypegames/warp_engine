module ForksHelpers
  def self.included(base)
    base.after { WarpEngine.config.forks = nil }
  end

  def configure_forks(**settings)
    WarpEngine.config.forks = WarpEngine::Forks::Configuration.new.tap do |config|
      config.allow_private_engines = true
      settings.each { |name, value| config.public_send(:"#{name}=", value) }
    end
  end
end
