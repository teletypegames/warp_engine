class CreateSyncServersAndEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_servers, id: { type: :bigint, unsigned: true },
                                charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :label, limit: 128, null: false
      t.string :host, limit: 255, null: false
      t.text :secret, null: false
      t.string :secret_prefix, limit: 12
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at, precision: 3
      t.text :last_error
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :deleted_at, name: "idx_sync_servers_deleted_at"
    end

    create_table :sync_events, id: { type: :bigint, unsigned: true },
                               charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :sync_server_id, unsigned: true
      t.string :direction, limit: 16, null: false
      t.string :status, limit: 16, null: false
      t.string :software_name, limit: 255
      t.string :platform, limit: 32
      t.string :version, limit: 128
      t.bigint :release_id, unsigned: true
      t.string :step, limit: 255
      t.integer :http_status
      t.text :message
      t.integer :files_count
      t.bigint :bytes
      t.integer :duration_ms
      t.integer :attempt
      t.string :token_prefix, limit: 12
      t.timestamps precision: 3, null: true
      t.index [ :sync_server_id, :created_at ], name: "idx_sync_events_server_created"
      t.index [ :software_name, :created_at ], name: "idx_sync_events_software_created"
      t.index :created_at, name: "idx_sync_events_created_at"
    end
    add_foreign_key :sync_events, :sync_servers, name: "fk_sync_servers_events", on_delete: :nullify

    add_column :softwares, :sync_enabled, :boolean
  end
end
