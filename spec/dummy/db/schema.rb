ActiveRecord::Schema[8.1].define(version: 2026_11_18_171937) do
  create_table "application_tokens", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.datetime "expires_at", precision: 3
    t.datetime "last_used_at", precision: 3
    t.string "name", limit: 128, null: false
    t.bigint "owner_id", null: false, unsigned: true
    t.string "owner_type", limit: 128, null: false
    t.json "scopes"
    t.string "token_digest", limit: 64, null: false
    t.string "token_prefix", limit: 12, null: false
    t.boolean "unrestricted", default: false, null: false
    t.datetime "updated_at", precision: 3
    t.index ["deleted_at"], name: "idx_application_tokens_deleted_at"
    t.index ["owner_type", "owner_id"], name: "idx_application_tokens_owner"
    t.index ["token_digest"], name: "idx_application_tokens_token_digest", unique: true
  end

  create_table "device_grants", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "application_token_id", unsigned: true
    t.datetime "approved_at", precision: 3
    t.string "client_name", limit: 128
    t.datetime "created_at", precision: 3
    t.datetime "denied_at", precision: 3
    t.string "device_code", limit: 64, null: false
    t.datetime "expires_at", precision: 3, null: false
    t.string "issued_token", limit: 64
    t.json "scopes"
    t.bigint "subject_id", unsigned: true
    t.string "subject_type", limit: 128
    t.datetime "updated_at", precision: 3
    t.string "user_code", limit: 16, null: false
    t.index ["device_code"], name: "idx_device_grants_device_code", unique: true
    t.index ["expires_at"], name: "idx_device_grants_expires_at"
    t.index ["user_code"], name: "idx_device_grants_user_code", unique: true
  end

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

  create_table "pipelines", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.datetime "last_pipeline_at", precision: 3
    t.string "last_pipeline_status", limit: 32
    t.string "platform", limit: 32, null: false
    t.string "repo_name", limit: 128, null: false
    t.string "repo_owner", limit: 128, null: false
    t.bigint "software_id", unsigned: true
    t.datetime "updated_at", precision: 3
    t.bigint "woodpecker_repo_id", null: false, unsigned: true
    t.index ["deleted_at"], name: "idx_pipelines_deleted"
    t.index ["repo_owner", "repo_name"], name: "idx_pipelines_owner_name", unique: true
    t.index ["software_id"], name: "idx_pipelines_software"
    t.index ["woodpecker_repo_id"], name: "idx_pipelines_wp_id", unique: true
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
    t.string "channel", limit: 16, default: "stable", null: false
    t.string "commit_sha", limit: 64
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.bigint "runtime_version_id", unsigned: true
    t.bigint "software_id", unsigned: true
    t.datetime "updated_at", precision: 3
    t.string "version", limit: 64
    t.string "web_binding", limit: 32
    t.json "web_options"
    t.index ["channel"], name: "idx_releases_channel"
    t.index ["commit_sha"], name: "idx_releases_commit_sha"
    t.index ["deleted_at"], name: "idx_releases_deleted_at"
    t.index ["runtime_version_id"], name: "idx_releases_runtime_version_id"
    t.index ["software_id"], name: "idx_releases_software_id"
  end

  create_table "runtime_components", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.string "key", limit: 64, null: false
    t.string "kind", limit: 32, null: false
    t.bigint "runtime_version_id", null: false, unsigned: true
    t.datetime "updated_at", precision: 3
    t.index ["runtime_version_id", "kind", "key"], name: "idx_runtime_components_version_kind_key", unique: true
  end

  create_table "runtime_versions", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.json "files"
    t.string "name", limit: 32, null: false
    t.string "path", null: false
    t.bigint "size_bytes", default: 0, null: false
    t.string "source", limit: 16, null: false
    t.datetime "updated_at", precision: 3
    t.string "version", limit: 64, null: false
    t.index ["deleted_at"], name: "idx_runtime_versions_deleted_at"
    t.index ["name", "version"], name: "idx_runtime_versions_name_version", unique: true
  end

  create_table "software_categories", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.string "key", limit: 64, null: false
    t.string "label", limit: 128, null: false
    t.boolean "needs_review", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", precision: 3
    t.index ["key"], name: "idx_software_categories_key", unique: true
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

  create_table "software_statuses", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "badge", limit: 32
    t.datetime "created_at", precision: 3
    t.boolean "default_visible", default: true, null: false
    t.string "key", limit: 32, null: false
    t.string "label", limit: 128, null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", precision: 3
    t.index ["key"], name: "idx_software_statuses_key", unique: true
  end

  create_table "softwares", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "author"
    t.string "category", limit: 64
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.text "desc"
    t.boolean "highlighted", default: false
    t.string "license", limit: 128
    t.string "name", limit: 128
    t.bigint "owner_id", unsigned: true
    t.string "owner_type", limit: 128
    t.string "platform", limit: 128
    t.string "shelf_name", limit: 32
    t.string "site"
    t.string "status", limit: 20, default: "development"
    t.text "story"
    t.boolean "sync_enabled"
    t.string "title"
    t.datetime "updated_at", precision: 3
    t.index ["deleted_at"], name: "idx_softwares_deleted_at"
    t.index ["name"], name: "idx_softwares_name", unique: true
    t.index ["owner_type", "owner_id"], name: "idx_softwares_owner"
  end

  create_table "sync_events", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "attempt"
    t.bigint "bytes"
    t.datetime "created_at", precision: 3
    t.string "direction", limit: 16, null: false
    t.integer "duration_ms"
    t.integer "files_count"
    t.integer "http_status"
    t.text "message"
    t.string "platform", limit: 32
    t.bigint "release_id", unsigned: true
    t.string "software_name"
    t.string "status", limit: 16, null: false
    t.string "step"
    t.bigint "sync_server_id", unsigned: true
    t.string "token_prefix", limit: 12
    t.datetime "updated_at", precision: 3
    t.string "version", limit: 128
    t.index ["created_at"], name: "idx_sync_events_created_at"
    t.index ["software_name", "created_at"], name: "idx_sync_events_software_created"
    t.index ["sync_server_id", "created_at"], name: "idx_sync_events_server_created"
  end

  create_table "sync_servers", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 3
    t.datetime "deleted_at", precision: 3
    t.string "host", null: false
    t.string "label", limit: 128, null: false
    t.text "last_error"
    t.datetime "last_synced_at", precision: 3
    t.text "secret", null: false
    t.string "secret_prefix", limit: 12
    t.datetime "updated_at", precision: 3
    t.index ["deleted_at"], name: "idx_sync_servers_deleted_at"
  end

  create_table "test_owners", id: { type: :bigint, unsigned: true }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", precision: 3
    t.string "name", limit: 128
    t.datetime "updated_at", precision: 3
  end

  add_foreign_key "downloads", "releases", name: "fk_downloads_release", on_delete: :nullify
  add_foreign_key "external_links", "softwares", name: "fk_softwares_external_links", on_delete: :cascade
  add_foreign_key "pipelines", "softwares", name: "fk_pipelines_software", on_delete: :nullify
  add_foreign_key "release_assets", "releases", name: "fk_releases_release_assets", on_delete: :cascade
  add_foreign_key "releases", "runtime_versions", name: "fk_runtime_versions_releases", on_delete: :nullify
  add_foreign_key "releases", "softwares", name: "fk_softwares_releases", on_delete: :cascade
  add_foreign_key "runtime_components", "runtime_versions", name: "fk_runtime_versions_components", on_delete: :cascade
  add_foreign_key "software_images", "images"
  add_foreign_key "software_images", "softwares", on_delete: :cascade
  add_foreign_key "sync_events", "sync_servers", name: "fk_sync_servers_events", on_delete: :nullify
end
