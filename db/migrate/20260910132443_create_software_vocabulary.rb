class CreateSoftwareVocabulary < ActiveRecord::Migration[8.1]
  def up
    create_table :software_statuses, id: { type: :bigint, unsigned: true },
                                     charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :key, limit: 32, null: false
      t.string :label, limit: 128, null: false
      t.integer :position, null: false, default: 0
      t.boolean :default_visible, null: false, default: true
      t.string :badge, limit: 32
      t.timestamps precision: 3, null: true
      t.index :key, name: "idx_software_statuses_key", unique: true
    end

    create_table :software_categories, id: { type: :bigint, unsigned: true },
                                       charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :key, limit: 64, null: false
      t.string :label, limit: 128, null: false
      t.integer :position, null: false, default: 0
      t.boolean :needs_review, null: false, default: false
      t.timestamps precision: 3, null: true
      t.index :key, name: "idx_software_categories_key", unique: true
    end

    statuses = Class.new(ActiveRecord::Base) { self.table_name = "software_statuses" }
    [
      [ "released",    "Released",       1, true,  "released" ],
      [ "demo",        "Demo",           2, true,  "demo" ],
      [ "development", "In development", 3, false, "development" ],
      [ "archived",    "Archived",       4, true,  nil ]
    ].each do |key, label, position, visible, badge|
      statuses.create!(key: key, label: label, position: position, default_visible: visible, badge: badge)
    end

    categories = Class.new(ActiveRecord::Base) { self.table_name = "software_categories" }
    keys = select_values("SELECT DISTINCT category FROM softwares WHERE category IS NOT NULL AND category <> ''")
    keys.sort.each_with_index do |key, index|
      categories.create!(key: key, label: key, position: index + 1, needs_review: true)
    end
  end

  def down
    drop_table :software_categories
    drop_table :software_statuses
  end
end
