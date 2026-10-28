module WarpEngine
  # Abstract base class of the engine's models.
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    # Lets Ransack (the ActiveAdmin filters) search every column.
    def self.ransackable_attributes(auth_object = nil)
      column_names
    end

    # Lets Ransack (the ActiveAdmin filters) search through every association.
    def self.ransackable_associations(auth_object = nil)
      reflect_on_all_associations.map(&:name).map(&:to_s)
    end
  end
end
