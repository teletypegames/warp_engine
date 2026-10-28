module WarpEngine
  # Compares the assets of the releases in the catalog with what their platform
  # expects, for the <tt>warp_engine:builds:check</tt> task: one Row per release
  # (or per software without a release).
  class AssetCoverage
    # The coverage of one release: the +software+, the +release+ (+nil+ when the
    # software has none), its WarpEngine::Platform (+nil+ when unknown), the
    # +expected+, +optional+ and +present+ asset kinds, and +ci_kinds+, the kinds
    # the CI adapter builds for the platform (+nil+ when it does not say).
    Row = Struct.new(:software, :release, :platform, :expected, :optional, :present, :ci_kinds, keyword_init: true) do
      # The expected kinds that are neither present nor optional.
      def missing = expected - present - optional.to_a

      # The missing kinds the CI builds (all missing kinds when +ci_kinds+ is +nil+).
      def buildable_missing
        return missing if ci_kinds.nil?

        missing & ci_kinds
      end

      # The missing kinds the CI does not build, which must be uploaded by hand.
      def manual_missing = missing - buildable_missing

      # The present kinds the platform does not expect.
      def unexpected = present - expected

      # Whether there is a release and nothing is missing.
      def complete? = release.present? && missing.empty?

      # Whether there is a release with a missing kind the CI could build.
      def actionable? = release.present? && buildable_missing.any?

      # Whether the software's platform is not registered.
      def unknown_platform? = platform.nil?

      # Whether the software has a release.
      def released? = release.present?

      # The version of the release, or +nil+.
      def version = release&.version

      # The state of +kind+ in the release: <tt>:present</tt>, <tt>:optional</tt>,
      # <tt>:manual</tt> (missing, and the CI does not build it) or <tt>:missing</tt>.
      def state_of(kind)
        return :present if present.include?(kind)
        return :optional if optional.to_a.include?(kind)
        return :manual if ci_kinds && !ci_kinds.include?(kind)

        :missing
      end
    end

    # [name]     only the software of this name (blank for all)
    # [platform] only the softwares of this platform (blank for all)
    # [releases] <tt>:latest</tt> (default) checks the latest non-dev release of
    #            each software, <tt>:all</tt> every release
    def initialize(name: nil, platform: nil, releases: :latest)
      @name = name.presence
      @platform = platform.presence
      @releases = releases == :all ? :all : :latest
    end

    # The filters given to #initialize.
    attr_reader :name, :platform, :releases

    # The Row of every selected release of the kept softwares matching the
    # filters, by software name.
    def rows
      @rows ||= scope.flat_map { |software| rows_for(software) }
    end

    # The rows with a missing kind the CI could build (Row#actionable?).
    def missing_rows = rows.select(&:actionable?)

    # The released rows that miss any kind (Row#complete? is false).
    def incomplete_rows = rows.select { |row| row.released? && !row.complete? }

    # Returns a Hash of counts over #rows: +softwares+, +releases+, +expected+,
    # +present+, +missing+ (buildable), +manual_missing+, +unexpected+,
    # +incomplete_softwares+, +without_release+ and +unknown_platform+. The
    # asset counts cover released rows only.
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
      relation = WarpEngine::Software.kept.order(:name).includes(releases: :release_assets)
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
        optional: WarpEngine::Platform.find(software.platform)&.optional_kinds || [],
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
      Release.latest_non_dev(all)
    end
  end
end
