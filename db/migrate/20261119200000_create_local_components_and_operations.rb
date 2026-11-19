class CreateLocalComponentsAndOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :local_components, id: { type: :bigint, unsigned: true } do |t|
      t.string :key, limit: 64, null: false
      t.string :role, limit: 32, null: false
      t.string :state, limit: 16, null: false, default: "off"
      t.json :settings
      t.text :secrets
      t.text :last_error
      t.timestamps precision: 3
    end
    add_index :local_components, :key, unique: true, name: "idx_local_components_key"

    create_table :local_operations, id: { type: :bigint, unsigned: true } do |t|
      t.string :kind, limit: 16, null: false
      t.string :target, limit: 128, null: false
      t.string :state, limit: 16, null: false, default: "queued"
      t.json :steps
      t.json :result
      t.text :error
      t.timestamps precision: 3
    end
    add_index :local_operations, :created_at, name: "idx_local_operations_created"
  end
end
