class AddBuildOwnership < ActiveRecord::Migration[8.1]
  def change
    # A publikáló token ownere; nil = belső / backfill előtti software.
    # Az owner osztályát a host adja (application_token_owner_class), ezért nem lehet FK.
    add_column :softwares, :owner_type, :string, limit: 128
    add_column :softwares, :owner_id, :bigint, unsigned: true
    add_index  :softwares, [ :owner_type, :owner_id ], name: "idx_softwares_owner"

    # unrestricted = belső token: az enforce_software_ownership nem vonatkozik rá.
    add_column :application_tokens, :unrestricted, :boolean, default: false, null: false
  end
end
