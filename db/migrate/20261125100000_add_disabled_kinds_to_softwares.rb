class AddDisabledKindsToSoftwares < ActiveRecord::Migration[8.1]
  def change
    add_column :softwares, :disabled_kinds, :json
  end
end
