module WarpEngine
  class AssetCoverageChecklist
    MARKERS = {
      present:    "[x]",
      missing:    "[ ]",
      manual:     "[-]",
      optional:   "[~]",
      unexpected: "[+]"
    }.freeze

    def initialize(coverage, only_missing: false)
      @coverage = coverage
      @only_missing = only_missing
    end

    attr_reader :coverage, :only_missing

    def lines
      [ *header, *body, *footer ]
    end

    def to_s = lines.join("\n")

    private

    def header
      [
        "WarpEngine release asset coverage — #{coverage.releases == :all ? 'every release' : 'latest release per software'}",
        "expected: the kinds a platform's updater registers · #{MARKERS[:missing]} the CI builds it · " \
        "#{MARKERS[:manual]} the CI does not, upload it by hand · #{MARKERS[:optional]} optional, may be absent",
        ""
      ]
    end

    def body
      shown = only_missing ? coverage.missing_rows : coverage.rows
      return [ "Nothing to report.", "" ] if shown.empty?

      shown.flat_map { |row| [ title(row), *checklist(row), "" ] }
    end

    def title(row)
      parts = [ row.software.name, row.platform&.name || "unknown platform" ]
      parts << (row.released? ? "v#{row.version}" : "no release")
      parts << ratio(row) if row.released? && row.expected.any?
      parts.join("  ")
    end

    def ratio(row) = "#{(row.expected & row.present).size}/#{row.expected.size}"

    def checklist(row)
      return [ "  (this platform is not in the registry, so nothing is expected)" ] if row.unknown_platform?
      return [ "  (no release to check)" ] unless row.released?
      return [ "  (this platform expects no assets)" ] if row.expected.empty? && row.present.empty?

      row.expected.map { |kind| "  #{MARKERS[row.state_of(kind)]} #{kind}" } +
        row.unexpected.map { |kind| "  #{MARKERS[:unexpected]} #{kind} (not expected on #{row.platform&.name})" }
    end

    def footer
      totals = coverage.totals
      lines = []

      if coverage.missing_rows.any? && !only_missing
        lines << "The CI can build these and the release does not have them:"
        lines += coverage.missing_rows.map do |row|
          "  #{row.software.name} v#{row.version} (#{row.platform&.name}): #{row.buildable_missing.join(', ')}"
        end
        lines << ""
      end

      lines << format(
        "%d softwares, %d releases, %d/%d assets present, %d missing from CI-built kinds",
        totals[:softwares], totals[:releases], totals[:present], totals[:expected], totals[:missing]
      )
      lines << "#{totals[:incomplete_softwares]} softwares are missing an asset the CI builds" if totals[:missing].positive?
      lines << "#{totals[:manual_missing]} assets are expected but this CI does not build them" if totals[:manual_missing].positive?
      lines << "#{totals[:without_release]} softwares have no release yet" if totals[:without_release].positive?
      lines << "#{totals[:unknown_platform]} softwares are on a platform the registry does not know" if totals[:unknown_platform].positive?
      lines << "#{totals[:unexpected]} assets are not expected on their platform" if totals[:unexpected].positive?
      lines
    end
  end
end
