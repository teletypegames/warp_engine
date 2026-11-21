class CreateForks < ActiveRecord::Migration[8.1]
  def up
    change_table :external_links, bulk: true do |t|
      t.string :kind, limit: 16, null: false, default: "link"
      t.string :ref, limit: 255
      t.boolean :public
      t.datetime :verified_at, precision: 3
      t.string :verify_error, limit: 512
    end
    add_index :external_links, [ :software_id, :kind ], name: "idx_external_links_software_kind"

    change_table :softwares, bulk: true do |t|
      t.boolean :forks_allowed, null: false, default: true
      t.string :fork_of_engine, limit: 255
      t.string :fork_of_name, limit: 128
      t.string :fork_of_version, limit: 64
      t.string :fork_of_repo, limit: 512
    end
    add_index :softwares, [ :fork_of_engine, :fork_of_name ], name: "idx_softwares_fork_of"

    create_table :fork_links, id: { type: :bigint, unsigned: true } do |t|
      t.bigint :software_id, unsigned: true, null: false
      t.string :child_engine, limit: 255, null: false
      t.string :child_name, limit: 128, null: false
      t.string :child_title, limit: 255
      t.string :status, limit: 16, null: false, default: "pending"
      t.datetime :checked_at, precision: 3
      t.string :last_error, limit: 512
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index [ :software_id, :child_engine, :child_name ], unique: true, name: "idx_fork_links_child"
      t.index :status, name: "idx_fork_links_status"
    end
    add_foreign_key :fork_links, :softwares, name: "fk_softwares_fork_links", on_delete: :cascade

    execute "UPDATE external_links SET kind = 'source' WHERE label = 'Repository' AND deleted_at IS NULL"
  end

  def down
    drop_table :fork_links
    remove_index :softwares, name: "idx_softwares_fork_of"
    remove_columns :softwares, :forks_allowed, :fork_of_engine, :fork_of_name, :fork_of_version, :fork_of_repo
    remove_index :external_links, name: "idx_external_links_software_kind"
    remove_columns :external_links, :kind, :ref, :public, :verified_at, :verify_error
  end
end
