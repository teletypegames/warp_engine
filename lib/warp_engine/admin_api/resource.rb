module WarpEngine
  module AdminApi
    class Resource
      UNAVAILABLE = { status: 404, message: "Not found" }.freeze

      attr_reader :name, :label, :scope, :operations, :unavailable

      def initialize(name, label:, scope: nil, condition: nil, unavailable: UNAVAILABLE, always: false, singular: nil)
        @name        = name.to_sym
        @label       = label
        @scope       = scope
        @condition   = condition
        @unavailable = unavailable
        @always      = always
        @singular    = singular
        @operations  = []
      end

      def always? = @always
      def singular = @singular || name.to_s.singularize
      def available? = @condition.nil? || @condition.call

      def list(path, summary:, item:, filters: {}, sort: {}, default_sort: nil, **options, &handler)
        query = filters.merge(
          page:    Schema.integer("Page number, from 1", minimum: 1),
          perPage: Schema.integer("Entries per page, capped by the host", minimum: 1)
        )
        if sort.any?
          orders = sort.keys.flat_map { |key| [ key.to_s, "-#{key}" ] }
          query[:sort] = Schema.enum(orders, "Order; a leading - reverses it. Default: #{default_sort || sort.keys.first}")
        end
        add(:list, :get, path, summary, handler, query: query, response: { kind: :page, item: item },
            sort: sort, default_sort: default_sort || sort.keys.first&.to_s, **options)
      end

      def get(path, summary:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :get, :get, path, summary, handler, response: { kind: :one, item: item },
            body_required: required, **options)
      end

      def create(path, summary:, body:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :create, :post, path, summary, handler,
            body: body, body_required: required, response: { kind: :one, item: item }, status: 201, **options)
      end

      def update(path, summary:, body:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :update, :patch, path, summary, handler,
            body: body, body_required: required, response: { kind: :one, item: item }, **options)
      end

      def delete(path, summary:, required: [], **options, &handler)
        add(options.delete(:name) || :delete, :delete, path, summary, handler, status: 204,
            body_required: required, **options)
      end

      def action(verb, path, name:, summary:, item: nil, many: false, required: [], status: nil, **options, &handler)
        response = if item.nil? then { kind: :none }
        elsif many then { kind: :many, item: item }
        else { kind: :one, item: item }
        end
        add(name, verb, path, summary, handler, response: response, body_required: required,
            status: status || (item ? 200 : 204), **options)
      end

      private

      def add(name, verb, path, summary, handler, **options)
        operation = Operation.new(resource: self, name: name, verb: verb, path: path, summary: summary,
                                  handler: handler, **options)
        @operations << operation
        operation
      end
    end
  end
end
