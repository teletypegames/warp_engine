module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::DeviceGrant: id, formatted user code,
    # client name, state, subject, issued token id, answer and expiry times and
    # timestamps. Never the device code or the issued token.
    class DeviceGrantSerializer < Blueprinter::Base
      identifier :id
      field(:userCode) { |grant| grant.formatted_user_code }
      field :client_name, name: :clientName
      field(:state) { |grant| grant.state.to_s }
      field :subject_type,         name: :subjectType
      field :subject_id,           name: :subjectId
      field :application_token_id, name: :applicationTokenId
      field :approved_at,          name: :approvedAt
      field :denied_at,            name: :deniedAt
      field :expires_at,           name: :expiresAt
      include Timestamps
    end
  end
end
