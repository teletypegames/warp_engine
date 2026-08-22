class CreateImages < ActiveRecord::Migration[8.0]
  def change
    create_table :images do |t|
      t.string :filename, null: false
      t.string :original_filename, null: false
      t.string :content_type, default: "application/octet-stream", null: false
      t.datetime :deleted_at, precision: 3
      t.timestamps
      t.index :deleted_at
    end
  end
end
