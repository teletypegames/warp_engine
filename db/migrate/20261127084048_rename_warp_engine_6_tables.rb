class RenameWarpEngine6Tables < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = {
    pipelines: :ci_repositories,
    fork_links: :software_forks,
    store_clients: :client_configs,
    local_components: :local_providers,
    local_operations: :local_tasks
  }.freeze

  INDEXES = {
    ci_repositories: { "idx_pipelines_deleted" => "idx_ci_repositories_deleted",
                       "idx_pipelines_owner_name" => "idx_ci_repositories_owner_name",
                       "idx_pipelines_software" => "idx_ci_repositories_software",
                       "idx_pipelines_wp_id" => "idx_ci_repositories_wp_id" },
    software_forks: { "idx_fork_links_child" => "idx_software_forks_engine_name",
                      "idx_fork_links_status" => "idx_software_forks_status" },
    client_configs: { "idx_store_clients_client" => "idx_client_configs_client" },
    local_providers: { "idx_local_components_key" => "idx_local_providers_key" },
    local_tasks: { "idx_local_operations_created" => "idx_local_tasks_created" }
  }.freeze

  FORK_COLUMNS = { child_engine: :engine_url, child_name: :name, child_title: :title }.freeze

  def up
    remove_foreign_key :pipelines, name: "fk_pipelines_software"
    remove_foreign_key :fork_links, name: "fk_softwares_fork_links"

    TABLES.each { |old, new| rename_table old, new }
    INDEXES.each { |table, names| names.each { |old, new| rename_index table, old, new } }
    FORK_COLUMNS.each { |old, new| rename_column :software_forks, old, new }
    rename_column :softwares, :shelf_name, :directory_name
    rename_column :downloads, :outlet, :feed

    add_foreign_key :ci_repositories, :softwares, name: "fk_ci_repositories_software", on_delete: :nullify
    add_foreign_key :software_forks, :softwares, name: "fk_softwares_software_forks", on_delete: :cascade
  end

  def down
    remove_foreign_key :ci_repositories, name: "fk_ci_repositories_software"
    remove_foreign_key :software_forks, name: "fk_softwares_software_forks"

    rename_column :downloads, :feed, :outlet
    rename_column :softwares, :directory_name, :shelf_name
    FORK_COLUMNS.each { |old, new| rename_column :software_forks, new, old }
    INDEXES.each { |table, names| names.each { |old, new| rename_index table, new, old } }
    TABLES.each { |old, new| rename_table new, old }

    add_foreign_key :pipelines, :softwares, name: "fk_pipelines_software", on_delete: :nullify
    add_foreign_key :fork_links, :softwares, name: "fk_softwares_fork_links", on_delete: :cascade
  end
end
