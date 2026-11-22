class CreateStoreClients < ActiveRecord::Migration[8.1]
  def change
    create_table :store_clients, id: { type: :bigint, unsigned: true } do |t|
      t.string :client, limit: 32, null: false
      t.string :software_name, limit: 128
      t.string :name, limit: 255
      t.string :store_key, limit: 64
      t.string :subfolder, limit: 128
      t.json :statuses
      t.json :logo_urls
      t.string :pinned_version, limit: 64
      t.timestamps precision: 3, null: true
      t.index :client, unique: true, name: "idx_store_clients_client"
    end
  end
end
