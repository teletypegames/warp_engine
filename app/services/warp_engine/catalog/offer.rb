require "json"

module WarpEngine
  # The catalog as the outlets (WarpEngine::Outlets) see it.
  module Catalog
    # What an outlet offers an anonymous caller: of every kept software of the
    # +platforms+ whose status is listed and which the access policy shows
    # without a gate, the latest release (WarpEngine::Release.latest_non_dev)
    # that has an asset of each of the +kinds+ whose file exists. One decision
    # shared by every outlet, so a shelf and a served outlet always list the
    # same titles.
    #
    #   offer = WarpEngine::Catalog::Offer.new(platforms: %w[c64], kinds: %w[cartridge])
    #   items, skips = offer.plan
    class Offer
      # One title and asset kind on offer: the +software+, the +release+ the
      # file comes from, the asset +kind+, the WarpEngine::ReleaseAsset
      # +asset+ and the absolute +source+ path of its file.
      Item = Struct.new(:software, :release, :kind, :asset, :source, keyword_init: true) do
        # Returns the size of the source file in bytes.
        def size = File.size(source)

        # Returns the extension of the source file in lower case, without the
        # dot (+prg+); the empty String when it has none.
        def extension = File.extname(source).delete_prefix(".").downcase

        # Returns the source path relative to +file_container_path+, as the
        # storage adapter and WarpEngine::DownloadService take it.
        def relative_path
          Pathname.new(source).relative_path_from(Pathname.new(WarpEngine.config.file_container_path.to_s)).to_s
        end

        # Returns the uploaded <tt>metadata.json</tt> of the release (it lies next
        # to the source as <tt>NAME-VERSION.metadata.json</tt>) as a Hash, or +nil+
        # when it is missing or not JSON.
        def metadata
          path = File.join(File.dirname(source), "#{software.name}-#{release.version}.metadata.json")
          File.file?(path) ? JSON.parse(File.read(path)) : nil
        rescue JSON::ParserError
          nil
        end
      end

      # A software that offers nothing, with the +reason+.
      Skip = Struct.new(:software, :reason, keyword_init: true) do
        # Returns <tt>"name: reason"</tt>.
        def to_s = "#{software.name}: #{reason}"
      end

      # The platform names, asset kinds and status keys of the offer (Arrays of
      # Strings; empty +statuses+ means the default visible ones).
      attr_reader :platforms, :kinds, :statuses

      # [platforms] the platform names
      # [kinds]     the WarpEngine::ReleaseAsset kinds, in the order they are considered
      # [statuses]  the status keys listed; empty for the default visible ones
      def initialize(platforms:, kinds:, statuses: [])
        @platforms = Array(platforms).map(&:to_s)
        @kinds = Array(kinds).map(&:to_s)
        @statuses = Array(statuses).map(&:to_s)
      end

      # Returns the status keys listed: #statuses, or the default visible keys
      # of WarpEngine::SoftwareStatus.
      def listed_statuses
        statuses.presence || WarpEngine::SoftwareStatus.default_visible_keys
      end

      # Returns the candidates: the kept softwares of the platforms with a
      # listed status that the access policy shows an anonymous caller, oldest
      # first, with their releases, assets and images loaded.
      def candidates
        listed = listed_statuses
        return WarpEngine::Software.none if listed.empty? || platforms.empty?

        WarpEngine.access_policy.visible_software_scope(subject: nil)
                  .where(platform: platforms, status: listed)
                  .includes({ releases: :release_assets }, { software_images: :image })
                  .order(:created_at, :id)
      end

      # Returns one <tt>[reason, item]</tt> pair for each kind of the offer, in
      # the order of #kinds: <tt>[nil, Item]</tt> when +software+ offers it,
      # <tt>[reason, nil]</tt> when it does not. A gated software gives the
      # single pair <tt>["gated", nil]</tt>.
      def consider(software)
        return [ [ "gated", nil ] ] if WarpEngine.access_policy.access_for(software: software, subject: nil).gated

        kinds.map do |kind|
          release, source = latest_with_asset(software, kind)
          next [ "no #{kind} asset in any release", nil ] if release.nil?

          asset = release.release_assets.find { |candidate| candidate.kind == kind }
          [ nil, Item.new(software: software, release: release, kind: kind, asset: asset, source: source) ]
        end
      end

      # Returns <tt>[items, skips]</tt>: every Item on offer, in the order of
      # #candidates and #kinds, and a Skip for each candidate that offers no kind.
      def plan
        items = []
        skips = []
        candidates.each do |software|
          pairs = consider(software)
          found = pairs.filter_map(&:last)
          skips << Skip.new(software: software, reason: pairs.filter_map(&:first).join("; ")) if found.empty?
          items.concat(found)
        end
        [ items, skips ]
      end

      # Returns every Item on offer (the first half of #plan).
      def items = plan.first

      # Returns the Items of the software with the id +software_id+, or an
      # empty Array when it is not on offer.
      def items_of(software_id)
        software = candidates.find_by(id: software_id)
        software ? consider(software).filter_map(&:last) : []
      end

      private

      def latest_with_asset(software, kind)
        sources = {}
        software.releases.each do |release|
          asset = release.release_assets.find { |candidate| candidate.kind == kind }
          path = asset && absolute(asset.path)
          sources[release] = path if path && File.file?(path)
        end
        release = WarpEngine::Release.latest_non_dev(sources.keys)
        release ? [ release, sources[release] ] : nil
      end

      def absolute(path)
        Pathname.new(path).absolute? ? path : File.join(WarpEngine.config.file_container_path, path)
      end
    end
  end
end
