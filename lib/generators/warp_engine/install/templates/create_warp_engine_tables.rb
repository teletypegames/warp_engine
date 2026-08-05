class CreateWarpEngineTables < ActiveRecord::Migration[8.0]
  def change
    create_table :softwares do |t|
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
      # A publikáló token ownere (enforce_software_ownership) — nem lehet FK,
      # az owner osztályát a host adja.
      t.string :owner_type, limit: 128
      t.bigint :owner_id
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :name, unique: true
      t.index [ :owner_type, :owner_id ]
      t.index :deleted_at
    end

    create_table :releases do |t|
      t.references :software, foreign_key: { on_delete: :cascade }
      t.string :version, limit: 64
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :deleted_at
    end

    create_table :release_assets do |t|
      t.references :release, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, limit: 32, null: false
      t.string :path, null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3
      t.index [ :release_id, :kind ], unique: true
      t.index :path
      t.index :deleted_at
    end

    create_table :external_links do |t|
      t.references :software, foreign_key: { on_delete: :cascade }
      t.string :label, limit: 128
      t.string :url
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :deleted_at
    end

    create_table :platform_links do |t|
      t.string :name, limit: 128
      t.string :platform, limit: 128
      t.string :url
      t.integer :position, default: 0, null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :platform
      t.index :deleted_at
    end

    create_table :images do |t|
      t.string :filename, null: false
      t.string :original_filename, null: false
      t.string :content_type, default: "application/octet-stream", null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps
      t.index :deleted_at
    end

    create_table :software_images do |t|
      t.references :software, null: false, foreign_key: { on_delete: :cascade }
      t.references :image, null: false, foreign_key: true, index: false
      t.boolean :is_default, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
      t.index [ :software_id, :image_id ], unique: true
      t.index [ :software_id, :position ]
    end

    create_table :application_tokens do |t|
      t.string :name, limit: 128, null: false
      t.string :owner_type, limit: 128, null: false
      t.bigint :owner_id, null: false
      t.string :token_digest, limit: 64, null: false
      t.string :token_prefix, limit: 12, null: false
      t.json :scopes
      # Belső token: az enforce_software_ownership nem vonatkozik rá.
      t.boolean :unrestricted, default: false, null: false
      t.datetime :expires_at, precision: 3
      t.datetime :last_used_at, precision: 3
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :token_digest, unique: true
      t.index [ :owner_type, :owner_id ]
      t.index :deleted_at
    end

    create_table :downloads do |t|
      t.string :file_path, null: false
      t.references :release, foreign_key: { on_delete: :nullify }, index: false
      t.string :ip_address
      t.string :user_agent, limit: 500
      t.string :referer, limit: 500
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :file_path
      t.index :release_id
      t.index :deleted_at
    end
  end
end
