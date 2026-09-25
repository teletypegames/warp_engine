module WarpEngine
  module AdminApi
    class Context
      attr_reader :operation, :principal, :params, :base_url, :via

      def initialize(operation:, principal:, params:, base_url:, via:)
        @operation = operation
        @principal = principal
        @params    = params
        @base_url  = base_url
        @via       = via
      end

      def [](key) = params[key.to_s]
      def key?(key) = params.key?(key.to_s)
      def id = self[:id]

      def attributes(*keys)
        names = keys.presence || operation.body&.dig(:properties)&.keys || []
        names.map(&:to_s).select { |key| params.key?(key) }.to_h { |key| [ key.underscore, params[key] ] }
      end

      def ok(data, meta: nil) = Result.new(status: 200, data: data, meta: meta)
      def created(data) = Result.new(status: 201, data: data)
      def no_content = Result.new(status: 204)

      def save!(record)
        raise Error.invalid(record) unless record.save

        record
      end

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
