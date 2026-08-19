require "rails_helper"

# The engine appends its `db/migrate` to the host's migration paths instead of copying
# migrations into the host, so the two share **one** version namespace. A collision does
# not fail politely somewhere in the engine: it stops the host's `db:migrate` before it
# runs anything, for the whole application.
#
# That is exactly what happened to `device_grants`. It was numbered 20260819000001 — a
# hand-picked round number — and the catalog API had written
# `20260819000001_carry_the_store_config_in_the_registry` on the same day with the same
# habit. Neither repository could see the other's number.
#
# The defence is that engine migrations carry a real second-resolution timestamp, which
# nobody hand-writes and nothing rounds to. This is the test that says so.
RSpec.describe "Engine migrations" do
  # `202608050000 01`-style numbers: a date, then zeros, then a counter. Rails generates
  # `20260819093412`; a person types this.
  ROUND_VERSION = /\A\d{8}0{4}\d{2}\z/

  # Numbered before this file existed and already deployed everywhere. Renumbering a
  # migration that has run is worse than the risk it carries, so they are named here
  # rather than quietly excluded by a rule that would also excuse the next one.
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

  # A table created by BOTH the install template and one of our own migrations is a
  # second CREATE TABLE for the same name in whatever host installs us — the template
  # runs, then the appended engine migration runs, and the second one fails.
  #
  # `application_tokens` is exactly that, and has been since before this file existed:
  # every host installing today has to delete that block from its generated copy by
  # hand, which is what teletype-orbit's own migration says in its header. It is
  # grandfathered here rather than quietly excused, so the list can only shrink.
  it "does not create a table the install generator also creates" do
    template = WarpEngine::Engine.root.join(
      "lib/generators/warp_engine/install/templates/create_warp_engine_tables.rb"
    )
    engine_tables = versions.flat_map do |version|
      file = Dir.glob(WarpEngine::Engine.root.join("db/migrate/#{version}_*.rb")).first
      File.read(file).scan(/create_table :(\w+)/).flatten
    end
    template_tables = File.read(template).scan(/create_table :(\w+)/).flatten
    duplicated = (engine_tables & template_tables) - [ "application_tokens" ]

    expect(duplicated).to be_empty,
                          "the install template and an engine migration both create " \
                          "#{duplicated.join(', ')} — a host would run CREATE TABLE twice. " \
                          "A table added after the initial schema belongs in a migration only."
  end
end
