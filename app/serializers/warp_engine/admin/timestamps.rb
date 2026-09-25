module WarpEngine
  module Admin
    module Timestamps
      def self.included(base)
        base.field :created_at, name: :createdAt
        base.field :updated_at, name: :updatedAt
      end
    end
  end
end
