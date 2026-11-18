require "rails_helper"
require "warp_engine/portable_migrations"

RSpec.describe WarpEngine::PortableMigrations do
  let(:adapter_class) do
    Class.new do
      def valid_column_definition_options = %i[limit null]
      def valid_primary_key_options = %i[limit]
    end
  end

  it "lets an adapter accept the MySQL-only column options, once" do
    described_class.install(adapter_class)
    described_class.install(adapter_class)
    adapter = adapter_class.new

    expect(adapter.valid_column_definition_options).to eq(%i[limit null unsigned auto_increment])
    expect(adapter.valid_primary_key_options).to eq(%i[limit unsigned auto_increment])
  end
end
