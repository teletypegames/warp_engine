module WarpEngine
  class DeviceGrantSerializer < Blueprinter::Base
    field(:deviceCode)      { |grant| grant.device_code }
    field(:userCode)        { |grant| grant.formatted_user_code }
    field(:verificationUrl) { |_grant, options| options[:verification_url] }
    field(:interval)        { WarpEngine.config.device_code_interval.to_i }
    field(:expiresIn)       { |grant| (grant.expires_at - Time.current).to_i }
  end
end
