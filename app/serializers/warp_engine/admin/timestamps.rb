module WarpEngine
  # Namespace of the Blueprinter serializers of the Admin API, rendering
  # records with camelCase keys.
  module Admin
    # Adds the +createdAt+ and +updatedAt+ fields to the Admin API serializer
    # that includes it.
    module Timestamps
      # Declares the +createdAt+ and +updatedAt+ fields on the including
      # serializer class +base+.
      def self.included(base)
        base.field :created_at, name: :createdAt
        base.field :updated_at, name: :updatedAt
      end
    end
  end
end
