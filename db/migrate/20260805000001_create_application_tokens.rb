class CreateApplicationTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :application_tokens, id: { type: :bigint, unsigned: true },
                                      charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, limit: 128, null: false
      # Az owner osztályát a host adja (WarpEngine.config.application_token_owner_class),
      # ezért nem lehet FK.
      t.string :owner_type, limit: 128, null: false
      t.bigint :owner_id, null: false, unsigned: true
      t.string :token_digest, limit: 64, null: false
      t.string :token_prefix, limit: 12, null: false
      t.json :scopes
      t.datetime :expires_at, precision: 3
      t.datetime :last_used_at, precision: 3
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true
      t.index :token_digest, name: "idx_application_tokens_token_digest", unique: true
      t.index [ :owner_type, :owner_id ], name: "idx_application_tokens_owner"
      t.index :deleted_at, name: "idx_application_tokens_deleted_at"
    end
  end
end
