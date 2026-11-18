module WarpEngine
  # Lets the engine's migrations, written for MySQL, run on the other
  # databases Rails speaks (SQLite for a local engine): the MySQL-only column
  # option +unsigned+ (and +auto_increment+) is accepted and left out there,
  # instead of failing with "Unknown key". The MySQL adapter knows these
  # options and is not touched.
  module PortableMigrations
    # The MySQL column options other adapters accept and ignore.
    MYSQL_ONLY_OPTIONS = %i[unsigned auto_increment].freeze

    # Adds MYSQL_ONLY_OPTIONS to the column options +adapter_class+ accepts.
    def self.install(adapter_class)
      adapter_class.prepend(ColumnOptions) unless adapter_class <= ColumnOptions
    end

    # Prepended to a non-MySQL adapter: the extra options pass the check.
    module ColumnOptions
      # The adapter's own valid column options and MYSQL_ONLY_OPTIONS.
      def valid_column_definition_options = super + MYSQL_ONLY_OPTIONS

      # The adapter's own valid primary key options and MYSQL_ONLY_OPTIONS.
      def valid_primary_key_options = super + MYSQL_ONLY_OPTIONS
    end
  end
end
