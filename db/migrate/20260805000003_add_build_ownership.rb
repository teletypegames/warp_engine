class AddBuildOwnership < ActiveRecord::Migration[8.1]
  def change

    add_column :softwares, :owner_type, :string, limit: 128
    add_column :softwares, :owner_id, :bigint, unsigned: true
    add_index  :softwares, [ :owner_type, :owner_id ], name: "idx_softwares_owner"

    add_column :application_tokens, :unrestricted, :boolean, default: false, null: false
  end
end
