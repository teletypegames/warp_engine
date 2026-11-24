class AddAppToSoftwares < ActiveRecord::Migration[8.1]
  def change
    add_column :softwares, :app, :string, limit: 16
  end
end
