module WarpEngine
  module Outlets
    class Assembly64 < Base
      # An AQL search as the Assembly64 clients send it: conditions of the form
      # <tt>(key:value)</tt> joined by <tt>&</tt>, the value quoted for a typed
      # text and bare for a value picked from a preset:
      #
      #   (name:"ariadne") & (category:games) & (date:2026)
      #
      # Keys are case-insensitive. Parentheses are optional, as some clients
      # leave them out; text that holds no condition gives an empty query.
      class Query
        # One condition: <tt>(key:"value")</tt> or <tt>(key:value)</tt>, with
        # optional parentheses.
        CONDITION = /\(?\s*([A-Za-z]+)\s*:\s*(?:"([^"]*)"|([^\s()&"]*))\s*\)?/

        # The conditions as an Array of <tt>[key, value]</tt> pairs, keys in
        # lower case, values stripped, in the order of the text.
        attr_reader :conditions

        # Parses +text+ (the decoded +query+ parameter) into a Query.
        def self.parse(text) = new(text.to_s.scan(CONDITION).map { |key, quoted, bare| [ key.downcase, (quoted || bare).strip ] })

        # [conditions] the <tt>[key, value]</tt> pairs
        def initialize(conditions)
          @conditions = conditions.reject { |_, value| value.empty? }
        end

        # Returns the last value given for +key+, or +nil+.
        def [](key) = conditions.reverse.find { |name, _| name == key.to_s }&.last

        # Returns the keys of the conditions.
        def keys = conditions.map(&:first).uniq

        # Returns +true+ when the query has no condition.
        def empty? = conditions.empty?
      end
    end
  end
end
