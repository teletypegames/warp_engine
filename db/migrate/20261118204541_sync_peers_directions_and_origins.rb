class SyncPeersDirectionsAndOrigins < ActiveRecord::Migration[8.1]
  class Peer < ActiveRecord::Base
    self.table_name = "sync_peers"
  end

  def up
    remove_foreign_key :sync_events, :sync_servers, name: "fk_sync_servers_events"
    rename_table :sync_servers, :sync_peers
    rename_index :sync_peers, "idx_sync_servers_deleted_at", "idx_sync_peers_deleted_at"

    rename_column :sync_peers, :active, :outbound_enabled
    change_column_null :sync_peers, :secret, true
    change_table :sync_peers, bulk: true do |t|
      t.string :transport, limit: 32, null: false, default: "http"
      t.json :transport_options
      t.boolean :inbound_enabled, null: false, default: true
      t.bigint :inbound_token_id, unsigned: true
    end
    Peer.reset_column_information
    Peer.find_each { |peer| peer.update_columns(transport_options: { "host" => peer.host }) }
    remove_column :sync_peers, :host

    rename_column :sync_events, :sync_server_id, :sync_peer_id
    rename_index :sync_events, "idx_sync_events_server_created", "idx_sync_events_peer_created"
    add_column :sync_events, :software_id, :bigint, unsigned: true
    add_index :sync_events, [ :software_id, :created_at ], name: "idx_sync_events_software_id_created"
    add_foreign_key :sync_events, :sync_peers, name: "fk_sync_peers_events", on_delete: :nullify
    execute <<~SQL
      UPDATE sync_events JOIN softwares ON softwares.name = sync_events.software_name
      SET sync_events.software_id = softwares.id
    SQL

    change_table :releases, bulk: true do |t|
      t.string :origin, limit: 8, null: false, default: "ci"
      t.bigint :sync_peer_id, unsigned: true
    end
  end

  def down
    remove_column :releases, :origin
    remove_column :releases, :sync_peer_id
    remove_foreign_key :sync_events, :sync_peers, name: "fk_sync_peers_events"
    remove_index :sync_events, name: "idx_sync_events_software_id_created"
    remove_column :sync_events, :software_id
    rename_index :sync_events, "idx_sync_events_peer_created", "idx_sync_events_server_created"
    rename_column :sync_events, :sync_peer_id, :sync_server_id

    add_column :sync_peers, :host, :string, limit: 255
    Peer.reset_column_information
    Peer.find_each { |peer| peer.update_columns(host: peer.transport_options.to_h["host"].to_s) }
    change_table :sync_peers, bulk: true do |t|
      t.remove :transport, :transport_options, :inbound_enabled, :inbound_token_id
    end
    rename_column :sync_peers, :outbound_enabled, :active
    rename_index :sync_peers, "idx_sync_peers_deleted_at", "idx_sync_servers_deleted_at"
    rename_table :sync_peers, :sync_servers
    add_foreign_key :sync_events, :sync_servers, name: "fk_sync_servers_events", on_delete: :nullify
  end
end
