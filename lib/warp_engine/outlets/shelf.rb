module WarpEngine
  module Outlets
    # A shelf as an outlet: a WarpEngine::Shelves shelf, written by
    # WarpEngine::ShelfService. The key is the shelf's path. Shelves are
    # configured with +shelf+ (or <tt>outlet ..., type: :shelf</tt>) and kept in
    # <tt>WarpEngine.config.shelves</tt>.
    class Shelf < Base
      include Materialized

      # Returns +shelf+.
      def self.type_name = "shelf"

      # The WarpEngine::Shelves::Shelf.
      attr_reader :shelf

      # [shelf] a WarpEngine::Shelves::Shelf
      def initialize(shelf)
        super(shelf.path, shelf.to_h)
        @shelf = shelf
      end

      # Returns the shelf's platform.
      def platforms = [ shelf.platform ]

      # Returns the WarpEngine::ShelfService#offer of the shelf.
      def offer = service.offer

      # Returns the Base#descriptor with the shelf's +kinds+, +layout+, +index+
      # file and +urls+.
      def descriptor
        super.merge(kinds: shelf.kinds, layout: shelf.layout, index: WarpEngine::Shelves::INDEX_FILE, urls: shelf.urls)
      end

      # Returns the WarpEngine::Shelves::Shelf#describe text.
      def describe = shelf.describe

      # Rebuilds the shelf through WarpEngine::ShelfService#sync!. Returns its
      # WarpEngine::ShelfService::Result.
      def sync!(dry_run: false) = service.sync!(dry_run: dry_run)

      # Returns the lines of the check: where the shelf is served, every file
      # on it and every software it leaves out.
      def report
        entries, skipped = service.plan
        shelf.urls.map { |url| "  served  #{url}" } +
          entries.map { |entry| "  ok      #{entry.file.ljust(shelf.name_length)} #{entry.version}  #{entry.software.name} (#{entry.kind})" } +
          skipped.map { |skip| "  skipped #{skip}" }
      end

      private

      def service = WarpEngine::ShelfService.new(shelf)
    end
  end
end
