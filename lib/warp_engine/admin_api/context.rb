module WarpEngine
  module AdminApi
    # What an operation handler gets: the Operation, the Principal, the coerced
    # params (string keys) and helpers that build a Result.
    class Context
      # The running Operation, the calling Principal, the params hash, the base URL
      # of the request and how it came: <tt>:http</tt> or <tt>:mcp</tt>.
      attr_reader :operation, :principal, :params, :base_url, :via

      # Builds the context; every argument becomes the reader of the same name.
      def initialize(operation:, principal:, params:, base_url:, via:)
        @operation = operation
        @principal = principal
        @params    = params
        @base_url  = base_url
        @via       = via
      end

      # The param named +key+.
      def [](key) = params[key.to_s]
      # Whether the param +key+ was given.
      def key?(key) = params.key?(key.to_s)
      # The +id+ path param.
      def id = self[:id]

      # The given params among +keys+ (by default the properties of the operation
      # body) as a hash with snake case keys, ready for <tt>assign_attributes</tt>.
      def attributes(*keys)
        names = keys.presence || operation.body&.dig(:properties)&.keys || []
        names.map(&:to_s).select { |key| params.key?(key) }.to_h { |key| [ key.underscore, params[key] ] }
      end

      # A 200 Result with +data+ and an optional +meta+.
      def ok(data, meta: nil) = Result.new(status: 200, data: data, meta: meta)
      # A 201 Result with +data+.
      def created(data) = Result.new(status: 201, data: data)
      # A 204 Result.
      def no_content = Result.new(status: 204)

      # Saves +record+ and returns it. Raises Error.invalid (422) when it does not validate.
      def save!(record)
        raise Error.invalid(record) unless record.save

        record
      end

      # One page of +scope+ as a 200 Result with pagination meta (page, perPage,
      # total, totalPages, nextPage). It honours the +page+, +perPage+ and +sort+
      # params; records are rendered with +serializer+, or with the block when given.
      # Raises a 400 Error for an unknown sort.
      def list(scope, serializer = nil, &block)
        per_page = per_page_value
        page     = [ self[:page].to_i, 1 ].max
        total    = scope.count
        records  = sorted(scope).offset((page - 1) * per_page).limit(per_page).to_a
        data     = block ? records.map(&block) : serializer.render_as_hash(records)
        pages    = (total / per_page.to_f).ceil

        ok(data, meta: { page: page, perPage: per_page, total: total, totalPages: pages,
                         nextPage: page < pages ? page + 1 : nil })
      end

      private

      def per_page_value
        config = AdminApi.config
        max = [ config.max_page_size.to_i, 1 ].max
        requested = self[:perPage].presence&.to_i || config.page_size.to_i
        requested.clamp(1, max)
      end

      def sorted(scope)
        columns = operation.sort_columns
        return scope if columns.empty?

        key = self[:sort].presence || operation.default_sort
        direction = key.start_with?("-") ? :desc : :asc
        column = columns[key.delete_prefix("-")]
        raise Error.bad_request("Unknown sort: #{key}") if column.nil?

        scope.reorder(column => direction, id: direction)
      end
    end
  end
end
