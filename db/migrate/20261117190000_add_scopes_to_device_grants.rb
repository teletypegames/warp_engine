class AddScopesToDeviceGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :device_grants, :scopes, :json
  end
end
