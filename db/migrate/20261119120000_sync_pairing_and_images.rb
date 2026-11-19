class SyncPairingAndImages < ActiveRecord::Migration[8.1]
  def change
    change_table :sync_peers, bulk: true do |t|
      t.json :allowed_channels
      t.string :created_by_type, limit: 128
      t.bigint :created_by_id, unsigned: true
    end
    add_index :sync_peers, [ :created_by_type, :created_by_id ], name: "idx_sync_peers_created_by"

    add_column :software_images, :origin, :string, limit: 8, null: false, default: "local"
  end
end
