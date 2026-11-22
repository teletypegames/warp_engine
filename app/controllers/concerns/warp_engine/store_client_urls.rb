module WarpEngine
  # Controller concern for the store engine endpoints
  # (<tt>/api/stores/:client/*</tt>): the addresses the installer, the store
  # config and the release answer name, worked out from the request.
  module StoreClientUrls
    extend ActiveSupport::Concern

    private

    def store_clients = WarpEngine::StoreClientService.new

    def catalog_url = "#{request.base_url}#{request.script_name}"

    def store_client_url(file) = "#{catalog_url}/api/stores/#{params[:client]}/#{file}"

    def release_path = "/api/stores/#{params[:client]}/release"

    def download_path(path) = "/api/download?#{{ path: path }.to_query}"
  end
end
