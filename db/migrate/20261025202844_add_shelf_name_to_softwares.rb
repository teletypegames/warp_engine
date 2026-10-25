class AddShelfNameToSoftwares < ActiveRecord::Migration[8.1]
  def change
    add_column :softwares, :shelf_name, :string, limit: 32 unless column_exists?(:softwares, :shelf_name)
  end
end
