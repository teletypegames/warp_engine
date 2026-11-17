module WarpEngine
  # Response of <tt>POST /api/auth/device</tt> for a WarpEngine::DeviceGrant:
  # +deviceCode+, +userCode+ (formatted), +verificationUrl+ (from the
  # +verification_url+ render option), +verificationUrlComplete+ (the same
  # with the user code in its +code+ parameter), the polling +interval+ in
  # seconds, +expiresIn+, the seconds left, and +scopes+, the Admin API scopes
  # a tool asked for (empty for a catalog client).
  class DeviceGrantSerializer < Blueprinter::Base
    field(:deviceCode)      { |grant| grant.device_code }
    field(:userCode)        { |grant| grant.formatted_user_code }
    field(:verificationUrl) { |_grant, options| options[:verification_url] }
    field(:verificationUrlComplete) do |grant, options|
      url = options[:verification_url].to_s
      "#{url}#{url.include?('?') ? '&' : '?'}code=#{grant.formatted_user_code}"
    end
    field(:scopes)          { |grant| Array(grant.scopes) }
    field(:interval)        { WarpEngine.config.device_code_interval.to_i }
    field(:expiresIn)       { |grant| (grant.expires_at - Time.current).to_i }
  end
end
