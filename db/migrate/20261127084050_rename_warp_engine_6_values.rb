class RenameWarpEngine6Values < ActiveRecord::Migration[8.1]
  class Software < ActiveRecord::Base
    self.table_name = "softwares"
  end

  KIND = { "cartridge" => "package" }.freeze
  ROLE = { "forge" => "scm" }.freeze

  def up
    rename_values(KIND, ROLE)
  end

  def down
    rename_values(KIND.invert, ROLE.invert)
  end

  private

  def rename_values(kinds, roles)
    kinds.each do |old, new|
      execute "UPDATE release_assets SET kind = #{quote(new)} WHERE kind = #{quote(old)}"
    end
    roles.each do |old, new|
      execute "UPDATE local_providers SET role = #{quote(new)} WHERE role = #{quote(old)}"
    end

    Software.reset_column_information
    Software.where.not(disabled_kinds: nil).find_each do |software|
      list = Array(software.disabled_kinds)
      renamed = list.map { |kind| kinds.fetch(kind.to_s, kind) }.uniq
      software.update_columns(disabled_kinds: renamed) unless renamed == list
    end
  end

  def quote(value) = connection.quote(value)
end
