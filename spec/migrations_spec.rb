require "rails_helper"

RSpec.describe "Engine migrations" do
  ROUND_VERSION = /\A\d{8}0{4}\d{2}\z/

  GRANDFATHERED = %w[
    20260805000001
    20260805000003
    20260806000001
    20260806000002
  ].freeze

  let(:versions) do
    Dir.glob(WarpEngine::Engine.root.join("db/migrate/*.rb"))
       .map { |path| File.basename(path)[/\A\d+/] }
  end

  it "has a migration to check at all" do
    expect(versions).not_to be_empty
  end

  it "numbers every migration uniquely" do
    expect(versions).to eq(versions.uniq)
  end

  it "uses a real timestamp rather than a round hand-written number" do
    round = versions.grep(ROUND_VERSION) - GRANDFATHERED

    expect(round).to be_empty,
                     "these would collide with a host that numbers its migrations the " \
                     "same way on the same day: #{round.join(', ')}. Use a second-resolution " \
                     "timestamp — `date -u +%Y%m%d%H%M%S` — not a hand-picked round number."
  end

  it "does not create a table the install generator also creates" do
    templates = Dir.glob(
      WarpEngine::Engine.root.join("lib/generators/warp_engine/install/templates/create_*.rb")
    )
    engine_tables = versions.flat_map do |version|
      file = Dir.glob(WarpEngine::Engine.root.join("db/migrate/#{version}_*.rb")).first
      File.read(file).scan(/create_table :(\w+)/).flatten
    end
    template_tables = templates.flat_map { |t| File.read(t).scan(/create_table :(\w+)/).flatten }
    duplicated = (engine_tables & template_tables) - [ "application_tokens" ]

    expect(duplicated).to be_empty,
                          "the install template and an engine migration both create " \
                          "#{duplicated.join(', ')} — a host would run CREATE TABLE twice. " \
                          "A table added after the initial schema belongs in a migration only."
  end
end
