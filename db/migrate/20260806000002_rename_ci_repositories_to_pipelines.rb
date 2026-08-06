class RenameCiRepositoriesToPipelines < ActiveRecord::Migration[8.1]
  def change
    rename_table :ci_repositories, :pipelines

    rename_index :pipelines, "idx_ci_repos_deleted",    "idx_pipelines_deleted"
    rename_index :pipelines, "idx_ci_repos_owner_name", "idx_pipelines_owner_name"
    rename_index :pipelines, "idx_ci_repos_software",   "idx_pipelines_software"
    rename_index :pipelines, "idx_ci_repos_wp_id",      "idx_pipelines_wp_id"

    remove_foreign_key :pipelines, :softwares,
                       column: :software_id, name: "fk_ci_repos_software", on_delete: :nullify
    add_foreign_key :pipelines, :softwares,
                    column: :software_id, name: "fk_pipelines_software", on_delete: :nullify
  end
end
