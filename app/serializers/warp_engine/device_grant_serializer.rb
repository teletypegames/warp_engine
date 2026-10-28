module WarpEngine
  # Response of <tt>POST /api/auth/device</tt> for a WarpEngine::DeviceGrant:
  # +deviceCode+, +userCode+ (formatted), +verificationUrl+ (from the
  # +verification_url+ render option), the polling +interval+ in seconds and
  # +expiresIn+, the seconds left.
  class DeviceGrantSerializer < Blueprinter::Base
    field(:deviceCode)      { |grant| grant.device_code }
    field(:userCode)        { |grant| grant.formatted_user_code }
    field(:verificationUrl) { |_grant, options| options[:verification_url] }
    field(:interval)        { WarpEngine.config.device_code_interval.to_i }
    field(:expiresIn)       { |grant| (grant.expires_at - Time.current).to_i }
  end
end
