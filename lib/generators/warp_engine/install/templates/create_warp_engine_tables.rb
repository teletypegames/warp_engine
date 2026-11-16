class CreateWarpEngineTables < ActiveRecord::Migration[8.1]
  def change
    create_table :softwares, id: { type: :bigint, unsigned: true },
                             charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, limit: 128
      t.string :title
      t.string :author
      t.text :desc
      t.text :story
      t.string :license, limit: 128
      t.string :platform, limit: 128
      t.string :site
      t.string :status, limit: 20, default: "development"
      t.boolean :highlighted, default: false
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :name, name: "idx_softwares_name", unique: true
      t.index :deleted_at, name: "idx_softwares_deleted_at"
    end

    create_table :releases, id: { type: :bigint, unsigned: true },
                            charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :software_id, unsigned: true
      t.string :version, limit: 64
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :software_id, name: "idx_releases_software_id"
      t.index :deleted_at, name: "idx_releases_deleted_at"
    end
    add_foreign_key :releases, :softwares, name: "fk_softwares_releases", on_delete: :cascade

    create_table :release_assets, id: { type: :bigint, unsigned: true },
                                  charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :release_id, null: false, unsigned: true
      t.string :kind, limit: 32, null: false
      t.string :path, null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3
      t.index [ :release_id, :kind ], name: "idx_release_assets_release_kind", unique: true
      t.index :path, name: "idx_release_assets_path"
      t.index :deleted_at, name: "idx_release_assets_deleted_at"
    end
    add_foreign_key :release_assets, :releases, name: "fk_releases_release_assets", on_delete: :cascade

    create_table :external_links, id: { type: :bigint, unsigned: true },
                                  charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :software_id, unsigned: true
      t.string :label, limit: 128
      t.string :url
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :software_id, name: "idx_external_links_software_id"
      t.index :deleted_at, name: "idx_external_links_deleted_at"
    end
    add_foreign_key :external_links, :softwares, name: "fk_softwares_external_links", on_delete: :cascade

    create_table :platform_links, id: { type: :bigint, unsigned: true },
                                  charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, limit: 128
      t.string :platform, limit: 128
      t.string :url
      t.integer :position, default: 0, null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :platform, name: "idx_platform_links_platform"
      t.index :deleted_at, name: "idx_platform_links_deleted_at"
    end

    create_table :software_images, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :software_id, null: false, unsigned: true
      t.bigint :image_id, null: false
      t.boolean :is_default, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
      t.index :image_id
      t.index [ :software_id, :image_id ], unique: true
      t.index [ :software_id, :position ]
    end
    add_foreign_key :software_images, :softwares, on_delete: :cascade

    create_table :downloads, id: { type: :bigint, unsigned: true },
                             charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :file_path, null: false
      t.bigint :release_id, unsigned: true
      t.string :ip_address
      t.string :user_agent, limit: 500
      t.string :referer, limit: 500
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :file_path
      t.index :release_id
      t.index :deleted_at, name: "idx_downloads_deleted_at"
    end
    add_foreign_key :downloads, :releases, name: "fk_downloads_release", on_delete: :nullify
  end
end
