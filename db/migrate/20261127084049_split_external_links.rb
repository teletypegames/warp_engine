class SplitExternalLinks < ActiveRecord::Migration[8.1]
  LINK_COLUMNS = %w[id software_id label url deleted_at created_at updated_at].freeze
  SOURCE_COLUMNS = %w[software_id url ref public verified_at verify_error deleted_at created_at updated_at].freeze

  def up
    create_table :software_links, id: { type: :bigint, unsigned: true } do |t|
      t.bigint :software_id, unsigned: true
      t.string :label, limit: 128
      t.string :url
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :software_id, name: "idx_software_links_software_id"
      t.index :deleted_at, name: "idx_software_links_deleted_at"
    end
    add_foreign_key :software_links, :softwares, name: "fk_softwares_software_links", on_delete: :cascade

    create_table :software_sources, id: { type: :bigint, unsigned: true } do |t|
      t.bigint :software_id, unsigned: true, null: false
      t.string :url
      t.string :ref, limit: 255
      t.boolean :public
      t.datetime :verified_at, precision: 3
      t.string :verify_error, limit: 512
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :software_id, name: "idx_software_sources_software_id"
      t.index :deleted_at, name: "idx_software_sources_deleted_at"
    end
    add_foreign_key :software_sources, :softwares, name: "fk_softwares_software_sources", on_delete: :cascade

    execute "INSERT INTO software_links (#{LINK_COLUMNS.join(', ')}) " \
            "SELECT #{LINK_COLUMNS.join(', ')} FROM external_links WHERE kind <> 'source' AND software_id IS NOT NULL"
    execute "INSERT INTO software_sources (#{SOURCE_COLUMNS.join(', ')}) " \
            "SELECT #{SOURCE_COLUMNS.join(', ')} FROM external_links WHERE kind = 'source' AND software_id IS NOT NULL"

    drop_table :external_links
  end

  def down
    create_table :external_links, id: { type: :bigint, unsigned: true } do |t|
      t.bigint :software_id, unsigned: true
      t.string :label, limit: 128
      t.string :url
      t.string :kind, limit: 16, null: false, default: "link"
      t.string :ref, limit: 255
      t.boolean :public
      t.datetime :verified_at, precision: 3
      t.string :verify_error, limit: 512
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :software_id, name: "idx_external_links_software_id"
      t.index :deleted_at, name: "idx_external_links_deleted_at"
      t.index [ :software_id, :kind ], name: "idx_external_links_software_kind"
    end
    add_foreign_key :external_links, :softwares, name: "fk_softwares_external_links", on_delete: :cascade

    execute "INSERT INTO external_links (#{LINK_COLUMNS.join(', ')}, kind) " \
            "SELECT #{LINK_COLUMNS.join(', ')}, 'link' FROM software_links"
    execute "INSERT INTO external_links (#{SOURCE_COLUMNS.join(', ')}, label, kind) " \
            "SELECT #{SOURCE_COLUMNS.join(', ')}, 'Repository', 'source' FROM software_sources"

    drop_table :software_sources
    drop_table :software_links
  end
end
