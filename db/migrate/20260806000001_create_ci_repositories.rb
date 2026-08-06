class CreateCiRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :ci_repositories, id: { type: :bigint, unsigned: true },
                                    charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint  :woodpecker_repo_id, null: false, unsigned: true
      t.string  :repo_owner, limit: 128, null: false
      t.string  :repo_name, limit: 128, null: false
      t.string  :platform, limit: 32, null: false
      t.bigint  :software_id, unsigned: true
      t.boolean :active, default: true, null: false
      t.string  :last_pipeline_status, limit: 32
      t.datetime :last_pipeline_at, precision: 3
      t.datetime :deleted_at, precision: 3
      t.timestamps precision: 3, null: true

      t.index :woodpecker_repo_id, unique: true, name: "idx_ci_repos_wp_id"
      t.index :software_id, name: "idx_ci_repos_software"
      t.index [ :repo_owner, :repo_name ], unique: true, name: "idx_ci_repos_owner_name"
      t.index :deleted_at, name: "idx_ci_repos_deleted"
    end

    add_foreign_key :ci_repositories, :softwares,
                    column: :software_id,
                    name: "fk_ci_repos_software",
                    on_delete: :nullify
  end
end
