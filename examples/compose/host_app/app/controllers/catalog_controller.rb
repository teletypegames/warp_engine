class CatalogController < ApplicationController
  layout "catalog"

  DESKTOP_DOWNLOADS = {
    "linux_x64" => "Linux",
    "win_x64" => "Windows",
    "mac_arm64" => "macOS (Apple Silicon)",
    "mac_x64" => "macOS (Intel)"
  }.freeze

  def index
    @apps, @games = catalog.partition { |entry| entry.dig("software", "platform") == "electron" }
  end

  def show
    @game = catalog.find { |entry| entry.dig("software", "name") == params[:name] }
    raise ActionController::RoutingError, "#{params[:name]} is not in the catalog" if @game.nil?
  end

  private

  def catalog
    JSON.parse(WarpEngine::SoftwareService.new.index.to_json).fetch("softwares")
  end
end
