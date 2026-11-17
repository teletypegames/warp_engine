class AddChannelToReleases < ActiveRecord::Migration[8.1]
  class Release < ActiveRecord::Base
    self.table_name = "releases"
  end

  def up
    add_column :releases, :channel, :string, limit: 16, null: false, default: "stable"
    add_index :releases, :channel, name: "idx_releases_channel"
    Release.reset_column_information
    Release.find_each do |release|
      version = release.version.to_s
      channel = if version.start_with?("dev-") then "dev"
      elsif version.delete_prefix("v").match?(/\A\d+(\.\d+)*-/) then "beta"
      else "stable"
      end
      release.update_columns(channel: channel) unless channel == "stable"
    end
  end

  def down
    remove_index :releases, name: "idx_releases_channel"
    remove_column :releases, :channel
  end
end
