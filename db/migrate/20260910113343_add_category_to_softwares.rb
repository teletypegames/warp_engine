class AddCategoryToSoftwares < ActiveRecord::Migration[8.1]
  def change
    add_column :softwares, :category, :string, limit: 64 unless column_exists?(:softwares, :category)
  end
end
