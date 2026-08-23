module WarpEngine
  class AssetCoverage
    Row = Struct.new(:software, :release, :platform, :expected, :present, :ci_kinds, keyword_init: true) do
      def missing = expected - present

      def buildable_missing
        return missing if ci_kinds.nil?

        missing & ci_kinds
      end

      def manual_missing = missing - buildable_missing

      def unexpected = present - expected

      def complete? = release.present? && missing.empty?

      def actionable? = release.present? && buildable_missing.any?

      def unknown_platform? = platform.nil?

      def released? = release.present?

      def version = release&.version

      def state_of(kind)
        return :present if present.include?(kind)
        return :manual if ci_kinds && !ci_kinds.include?(kind)

        :missing
      end
    end

    def initialize(name: nil, platform: nil, releases: :latest)
      @name = name.presence
      @platform = platform.presence
      @releases = releases == :all ? :all : :latest
    end

    attr_reader :name, :platform, :releases

    def rows
      @rows ||= scope.flat_map { |software| rows_for(software) }
    end

    def missing_rows = rows.select(&:actionable?)

    def incomplete_rows = rows.select { |row| row.released? && !row.complete? }

    def totals
      counted = rows.select(&:released?)

      {
        softwares:            rows.map { |row| row.software.id }.uniq.size,
        releases:             counted.size,
        expected:             counted.sum { |row| row.expected.size },
        present:              counted.sum { |row| (row.expected & row.present).size },
        missing:              counted.sum { |row| row.buildable_missing.size },
        manual_missing:       counted.sum { |row| row.manual_missing.size },
        unexpected:           counted.sum { |row| row.unexpected.size },
        incomplete_softwares: missing_rows.map { |row| row.software.id }.uniq.size,
        without_release:      rows.count { |row| !row.released? },
        unknown_platform:     rows.count(&:unknown_platform?)
      }
    end

    private

    def scope
      relation = WarpEngine::Software.order(:name).includes(releases: :release_assets)
      relation = relation.where(name: name) if name
      relation = relation.where(platform: platform) if platform
      relation
    end

    def rows_for(software)
      expected = expected_kinds(software)
      selected = select_releases(software.releases.to_a)
      return [ row(software, nil, expected) ] if selected.empty?

      selected.map { |release| row(software, release, expected) }
    end

    def row(software, release, expected)
      Row.new(
        software: software,
        release:  release,
        platform: WarpEngine::Platform.find(software.platform),
        expected: expected,
        present:  release ? release.release_assets.map(&:kind).uniq : [],
        ci_kinds: ci_kinds(software.platform)
      )
    end

    def ci_kinds(platform)
      @ci_kinds ||= {}
      return @ci_kinds[platform] if @ci_kinds.key?(platform)

      ci = WarpEngine.ci
      @ci_kinds[platform] = ci.respond_to?(:built_kinds) ? ci.built_kinds(platform) : nil
    end

    def expected_kinds(software)
      WarpEngine::Platform.find(software.platform)&.expected_kinds || []
    end

    def select_releases(all)
      return sorted(all) if releases == :all

      [ latest(all) ].compact
    end

    def sorted(all) = all.sort_by { |release| [ release.created_at || Time.at(0), release.id ] }.reverse

    def latest(all)
      candidates = all.reject { |release| release.version.to_s.start_with?("dev-") }
      candidates = all if candidates.empty?
      sorted(candidates).first
    end
  end
end
