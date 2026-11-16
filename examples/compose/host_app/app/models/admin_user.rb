class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable

  def self.ransackable_attributes(auth_object = nil)
    %w[created_at email id updated_at]
  end
end
