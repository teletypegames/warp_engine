class AddBuildOwnership < ActiveRecord::Migration[8.1]
  def change
    # Owner of the publishing token; nil = internal / pre-backfill software.
    # The owner class comes from the host (application_token_owner_class), so no FK.
    add_column :softwares, :owner_type, :string, limit: 128
    add_column :softwares, :owner_id, :bigint, unsigned: true
    add_index  :softwares, [ :owner_type, :owner_id ], name: "idx_softwares_owner"

    # unrestricted = internal token: exempt from enforce_software_ownership.
    add_column :application_tokens, :unrestricted, :boolean, default: false, null: false
  end
end
