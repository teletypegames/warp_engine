class AddCommitShaToReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :releases, :commit_sha, :string, limit: 64
    add_index :releases, :commit_sha, name: "idx_releases_commit_sha"
  end
end
