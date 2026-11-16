class CreateRuntimeVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :runtime_versions, id: { type: :bigint, unsigned: true },
                                    charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, limit: 32, null: false
      t.string :version, limit: 64, null: false
      t.string :source, limit: 16, null: false
      t.string :path, limit: 255, null: false
      t.json :files
      t.bigint :size_bytes, null: false, default: 0
      t.timestamps precision: 3, null: true
      t.datetime :deleted_at, precision: 3
      t.index [ :name, :version ], name: "idx_runtime_versions_name_version", unique: true
      t.index :deleted_at, name: "idx_runtime_versions_deleted_at"
    end

    create_table :runtime_components, id: { type: :bigint, unsigned: true },
                                      charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :runtime_version_id, unsigned: true, null: false
      t.string :kind, limit: 32, null: false
      t.string :key, limit: 64, null: false
      t.timestamps precision: 3, null: true
      t.index [ :runtime_version_id, :kind, :key ], name: "idx_runtime_components_version_kind_key", unique: true
    end
    add_foreign_key :runtime_components, :runtime_versions, name: "fk_runtime_versions_components", on_delete: :cascade

    change_table :releases, bulk: true do |t|
      t.bigint :runtime_version_id, unsigned: true
      t.string :web_binding, limit: 32
      t.json :web_options
      t.index :runtime_version_id, name: "idx_releases_runtime_version_id"
    end
    add_foreign_key :releases, :runtime_versions, name: "fk_runtime_versions_releases", on_delete: :nullify
  end
end
