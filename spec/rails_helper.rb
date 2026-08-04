require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# A factory_bot_rails a dummy app gyökerében keresne; a factory-k az engine spec/ alatt élnek
FactoryBot.definition_file_paths = [ File.expand_path("factories", __dir__) ]
FactoryBot.reload

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
