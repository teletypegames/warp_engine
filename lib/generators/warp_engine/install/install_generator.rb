require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record"

module WarpEngine
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/warp_engine.rb"
      end

      def copy_image_library
        template "image.rb", "app/models/image.rb"
        template "images_controller.rb", "app/controllers/api/images_controller.rb"
        migration_template "create_images.rb", "db/migrate/create_images.rb"
      end

      def copy_migration
        migration_template "create_warp_engine_tables.rb", "db/migrate/create_warp_engine_tables.rb"
      end

      def show_readme
        say <<~MSG

          WarpEngine telepítve. Következő lépések:
            1. rails db:migrate
            2. mount WarpEngine::Engine => "/" a config/routes.rb végére
            3. a képkönyvtár a hosztod: a routes.rb-be
               namespace :api do
                 get "image/:id", to: "images#show"
               end
            4. állítsd be a config/initializers/warp_engine.rb-t
        MSG
      end
    end
  end
end
