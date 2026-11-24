class AddClientIdAndOutletToDownloads < ActiveRecord::Migration[8.1]
  def change
    add_column :downloads, :client_id, :string, limit: 100
    add_column :downloads, :outlet, :string, limit: 32
    add_index :downloads, :outlet
  end
end
