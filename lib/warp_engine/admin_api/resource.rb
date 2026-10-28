module WarpEngine
  module AdminApi
    # A group of Admin API operations on one kind of record, e.g. softwares. Its
    # methods declare the operations; each takes a block that gets a Context and
    # returns a Result.
    class Resource
      # The answer when the resource's condition does not hold, unless it names another.
      UNAVAILABLE = { status: 404, message: "Not found" }.freeze

      # The resource name (symbol), its label (the OpenAPI tag), the scope its
      # operations need by default, its operations and the status and message
      # answered while unavailable.
      attr_reader :name, :label, :scope, :operations, :unavailable

      # [name]        the resource name
      # [label]       a human name
      # [scope]       the scope its operations need, or +nil+ for read/write by verb
      # [condition]   a callable; while it returns false the resource is unavailable
      # [unavailable] <tt>{ status:, message: }</tt> answered while unavailable
      # [always]      served even when Configuration#resources leaves it out
      # [singular]    the singular name used in MCP tool names
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

      # Whether the resource is served regardless of Configuration#resources.
      def always? = @always
      # The singular name, by default the singularized #name.
      def singular = @singular || name.to_s.singularize
      # Whether the condition holds (always true without one).
      def available? = @condition.nil? || @condition.call

      # Declares a paginated GET +path+ named +list+. Adds the +page+ and +perPage+
      # query params, and a +sort+ param when +sort+ maps sort keys to columns.
      #
      # [summary]      one line on what it does
      # [item]         the Definitions::Schemas::Named of one entry
      # [filters]      query param schemas, by name
      # [sort]         sort key to column
      # [default_sort] the sort key used without +sort+, by default the first one
      #
      # Returns the Operation.
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

      # Declares a GET +path+ answering one +item+ (named +get+ unless <tt>name:</tt> says otherwise).
      def get(path, summary:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :get, :get, path, summary, handler, response: { kind: :one, item: item },
            body_required: required, **options)
      end

      # Declares a POST +path+ with a JSON +body+ answering 201 with one +item+.
      def create(path, summary:, body:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :create, :post, path, summary, handler,
            body: body, body_required: required, response: { kind: :one, item: item }, status: 201, **options)
      end

      # Declares a PATCH +path+ with a JSON +body+ answering one +item+.
      def update(path, summary:, body:, item:, required: [], **options, &handler)
        add(options.delete(:name) || :update, :patch, path, summary, handler,
            body: body, body_required: required, response: { kind: :one, item: item }, **options)
      end

      # Declares a DELETE +path+ answering 204.
      def delete(path, summary:, required: [], **options, &handler)
        add(options.delete(:name) || :delete, :delete, path, summary, handler, status: 204,
            body_required: required, **options)
      end

      # Declares any other operation: +verb+ and +path+ under +name+. With an +item+
      # it answers one entry (or a list of them when +many+), without it 204.
      # +status+ overrides the success status.
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
