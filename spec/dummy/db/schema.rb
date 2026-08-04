# A katalógus-táblák a host schema.rb-vel megegyező definícióval.
ActiveRecord::Schema[8.1].define(version: 1) do
  create_table "downloads", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.string "file_path", null: false
    t.string "ip_address"
    t.string "referer", limit: 500
    t.bigint "release_id", unsigned: true
    t.datetime "updated_at", precision: 3
    t.string "user_agent", limit: 500
    t.index ["deleted_at"], name: "idx_downloads_deleted_at"
    t.index ["file_path"], name: "index_downloads_on_file_path"
    t.index ["release_id"], name: "index_downloads_on_release_id"
  end

  create_table "external_links", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.string "label", limit: 128
    t.bigint "software_id", unsigned: true
    t.datetime "updated_at", precision: 3
    t.string "url"
    t.index ["deleted_at"], name: "idx_external_links_deleted_at"
    t.index ["software_id"], name: "idx_external_links_software_id"
  end

  create_table "images", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "content_type", default: "application/octet-stream", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: 3
    t.string "filename", null: false
    t.string "original_filename", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "idx_images_deleted_at"
  end

  create_table "platform_links", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.string "name", limit: 128
    t.string "platform", limit: 128
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", precision: 3
    t.string "url"
    t.index ["deleted_at"], name: "idx_platform_links_deleted_at"
    t.index ["platform"], name: "idx_platform_links_platform"
  end

  create_table "release_assets", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3, null: false
    t.datetime "deleted_at", precision: 3
    t.string "kind", limit: 32, null: false
    t.string "path", null: false
    t.bigint "release_id", null: false, unsigned: true
    t.datetime "updated_at", precision: 3, null: false
    t.index ["deleted_at"], name: "idx_release_assets_deleted_at"
    t.index ["path"], name: "idx_release_assets_path"
    t.index ["release_id", "kind"], name: "idx_release_assets_release_kind", unique: true
  end

  create_table "releases", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.bigint "software_id", unsigned: true
    t.datetime "updated_at", precision: 3
    t.string "version", limit: 64
    t.index ["deleted_at"], name: "idx_releases_deleted_at"
    t.index ["software_id"], name: "idx_releases_software_id"
  end

  create_table "software_images", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "image_id", null: false
    t.boolean "is_default", default: false, null: false
    t.integer "position", default: 0, null: false
    t.bigint "software_id", null: false, unsigned: true
    t.datetime "updated_at", null: false
    t.index ["image_id"], name: "fk_rails_a456fbc278"
    t.index ["software_id", "image_id"], name: "index_software_images_on_software_id_and_image_id", unique: true
    t.index ["software_id", "position"], name: "index_software_images_on_software_id_and_position"
  end

  create_table "softwares", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "author"
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.text "desc"
    t.boolean "highlighted", default: false
    t.string "license", limit: 128
    t.string "name", limit: 128
    t.string "platform", limit: 128
    t.string "site"
    t.string "status", limit: 20, default: "development"
    t.text "story"
    t.string "title"
    t.datetime "updated_at", precision: 3
    t.index ["deleted_at"], name: "idx_softwares_deleted_at"
    t.index ["name"], name: "idx_softwares_name", unique: true
  end

  add_foreign_key "downloads", "releases", name: "fk_downloads_release", on_delete: :nullify
  add_foreign_key "external_links", "softwares", name: "fk_softwares_external_links", on_delete: :cascade
  add_foreign_key "release_assets", "releases", name: "fk_releases_release_assets", on_delete: :cascade
  add_foreign_key "releases", "softwares", name: "fk_softwares_releases", on_delete: :cascade
  add_foreign_key "software_images", "images"
  add_foreign_key "software_images", "softwares", on_delete: :cascade
end
