require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record"

module WarpEngine
  # The engine's Rails generators.
  module Generators
    # <tt>rails g warp_engine:install</tt>: copies the initializer, the host
    # image library (model, controller, migration) and the engine's migration
    # into the host application.
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      # Returns the next migration timestamp for +dirname+.
      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      # Writes <tt>config/initializers/warp_engine.rb</tt>.
      def copy_initializer
        template "initializer.rb", "config/initializers/warp_engine.rb"
      end

      # Writes the image model, <tt>Api::ImagesController</tt> and the migration
      # creating the +images+ table.
      def copy_image_library
        template "image.rb", "app/models/image.rb"
        template "images_controller.rb", "app/controllers/api/images_controller.rb"
        migration_template "create_images.rb", "db/migrate/create_images.rb"
      end

      # Writes the migration creating the engine's tables.
      def copy_migration
        migration_template "create_warp_engine_tables.rb", "db/migrate/create_warp_engine_tables.rb"
      end

      # Prints the next steps of the installation.
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
