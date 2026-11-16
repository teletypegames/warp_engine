require "erb"
require "json"

module WarpEngine
  class Runtime
    # Fills a runtime's page template. The template is plain HTML with two
    # kinds of placeholder, each naming a value by a dotted path:
    #
    # [<tt>{{ title }}</tt>]           the value, HTML-escaped (text and attributes)
    # [<tt>{{ json params.core }}</tt>] the value as JSON, safe inside a <tt><script></tt>
    #
    # A path that names nothing gives an empty string (JSON +null+). The
    # template runs no code.
    #
    #   WarpEngine::Runtime::Template.render("<h1>{{ title }}</h1>", title: "A & B")
    #   # => "<h1>A &amp; B</h1>"
    module Template
      # The placeholder pattern.
      PLACEHOLDER = /\{\{\s*(json\s+)?([a-zA-Z0-9_.]+)\s*\}\}/

      module_function

      # Returns +source+ with every placeholder replaced from +values+ (a Hash).
      def render(source, values)
        source.gsub(PLACEHOLDER) do
          value = lookup(values, Regexp.last_match(2))
          Regexp.last_match(1) ? json(value) : ERB::Util.html_escape(value.to_s)
        end
      end

      # Returns the value at the dotted +path+ of +values+, or +nil+.
      def lookup(values, path)
        path.split(".").reduce(values) do |current, key|
          break nil unless current.is_a?(Hash)

          current.key?(key) ? current[key] : current[key.to_sym]
        end
      end

      # Returns +value+ as JSON with <tt><</tt>, <tt>></tt>, <tt>&</tt> and the
      # line separators escaped, so it cannot close a script element.
      def json(value)
        JSON.generate(value).gsub("<", "\\u003c").gsub(">", "\\u003e").gsub("&", "\\u0026")
            .gsub("\u2028", "\\u2028").gsub("\u2029", "\\u2029")
      end
    end
  end
end
