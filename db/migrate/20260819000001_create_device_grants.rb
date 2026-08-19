class CreateDeviceGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :device_grants, id: { type: :bigint, unsigned: true },
                                 charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      # Both codes are secrets in the sense that guessing one grants a session, but they
      # have different jobs: the device code is long and never shown to a person, the
      # user code is short enough to read off a screen and type into a browser.
      t.string :device_code, limit: 64, null: false
      t.string :user_code, limit: 16, null: false
      # What the client called itself. Shown on the approval page, so a person can tell
      # which machine is asking, and kept on the issued token as its name.
      t.string :client_name, limit: 128
      # The approving subject comes from the host
      # (WarpEngine.config.access_token_owner_class), so no FK — same reasoning as
      # application_tokens.owner_type.
      t.string :subject_type, limit: 128
      t.bigint :subject_id, unsigned: true
      t.bigint :application_token_id, unsigned: true
      # The issued token, in the clear, for the seconds between "approved" and "the
      # client's next poll". It is cleared on the poll that hands it over, so this
      # column holds a live secret only while somebody is waiting for it. There is no
      # way around storing it: the approval happens in a browser and the poll arrives on
      # a different request, so the two cannot share memory. Everything else about a
      # token is stored as a digest — this is the one exception, and it is temporary.
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
