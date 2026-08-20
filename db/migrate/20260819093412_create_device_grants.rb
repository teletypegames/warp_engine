class CreateDeviceGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :device_grants, id: { type: :bigint, unsigned: true },
                                 charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|

      t.string :device_code, limit: 64, null: false
      t.string :user_code, limit: 16, null: false

      t.string :client_name, limit: 128

      t.string :subject_type, limit: 128
      t.bigint :subject_id, unsigned: true
      t.bigint :application_token_id, unsigned: true

      t.string :issued_token, limit: 64
      t.datetime :approved_at, precision: 3
      t.datetime :denied_at, precision: 3
      t.datetime :expires_at, precision: 3, null: false
      t.timestamps precision: 3, null: true
      t.index :device_code, name: "idx_device_grants_device_code", unique: true
      t.index :user_code, name: "idx_device_grants_user_code", unique: true
      t.index :expires_at, name: "idx_device_grants_expires_at"
    end
  end
end
