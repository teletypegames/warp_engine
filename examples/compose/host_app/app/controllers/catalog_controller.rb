class CatalogController < ApplicationController
  layout "catalog"

  def index
    @games = catalog
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
