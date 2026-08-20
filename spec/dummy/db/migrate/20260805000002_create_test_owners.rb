class CreateTestOwners < ActiveRecord::Migration[8.1]
  def change
    create_table :test_owners, id: { type: :bigint, unsigned: true },
                               charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, limit: 128
      t.timestamps precision: 3, null: true
    end
  end
end
