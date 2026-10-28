module WarpEngine
  # Controller concern that turns exceptions into JSON error responses.
  #
  # Including it installs +rescue_from+ handlers that render
  # <tt>{ "error": ... }</tt> with:
  #
  # [ActiveRecord::RecordNotFound, Errno::ENOENT] 404 <tt>Not found</tt>
  # [ArgumentError]                              400 with the exception message
  # [any other StandardError]                    500 <tt>Internal server error</tt>,
  #                                              after logging the exception
  module ApiErrorRendering
    extend ActiveSupport::Concern

    included do
      rescue_from StandardError do |e|
        Rails.logger.error("[#{self.class.name}] #{e.class}: #{e.message}")
        render json: { error: "Internal server error" }, status: :internal_server_error
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "Not found" }, status: :not_found
      end

      rescue_from Errno::ENOENT do
        render json: { error: "Not found" }, status: :not_found
      end

      rescue_from ArgumentError do |e|
        render json: { error: e.message }, status: :bad_request
      end
    end

    private

    def resolve_mime(path) = WarpEngine::Storage.mime_for(path)
  end
end
