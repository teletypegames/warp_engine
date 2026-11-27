module WarpEngine
  class Runtime
    # The controls help of a web player: what the keys do in the runtime a
    # release plays in. It is a list of rows, each a Hash with
    #
    # [keys]   the keys, as <tt>KeyboardEvent.code</tt> values (+KeyZ+,
    #          +ArrowUp+, +Space+, ...) or an ALIASES name; any of them does
    #          the action. Empty for a row that only says something.
    # [action] what they do, in English
    #
    # A runtime generates rows from the parameters a release plays with
    # (Builder#controls), a platform binding adds its own
    # (WarpEngine::Platform::WebBinding#controls).
    module Controls
      # The key names that are not a <tt>KeyboardEvent.code</tt>.
      ALIASES = %w[Gamepad].freeze

      # The <tt>KeyboardEvent.code</tt> values a row may name.
      CODE = /\A(?:Key[A-Z]|Digit[0-9]|F(?:[1-9]|1[0-9]|2[0-4])|Arrow(?:Up|Down|Left|Right)|
                 Numpad(?:[0-9]|Add|Subtract|Multiply|Divide|Decimal|Enter)|(?:Shift|Control|Alt|Meta)(?:Left|Right)|
                 Space|Enter|Escape|Backspace|Tab|CapsLock|Backquote|Minus|Equal|BracketLeft|BracketRight|Backslash|
                 Semicolon|Quote|Comma|Period|Slash|IntlBackslash|Insert|Delete|Home|End|PageUp|PageDown)\z/x

      module_function

      # Returns a row of +keys+ (one or a list) doing +action+.
      def row(keys, action) = { "keys" => Array(keys).map(&:to_s).freeze, "action" => action.to_s }.freeze

      # Returns +rows+ (Hashes with String or Symbol keys, or +nil+) as frozen
      # rows with String keys.
      def normalize(rows)
        Array(rows).map do |entry|
          entry = entry.to_h.transform_keys(&:to_s)
          row(entry["keys"], entry["action"])
        end.freeze
      end

      # Returns the problems of +rows+ as messages: not a list, a row without
      # an action, a key that is neither a code nor an alias. Empty when they
      # fit.
      def errors(rows)
        return [ "controls must be a list" ] unless rows.nil? || rows.is_a?(Array)

        Array(rows).each_with_index.flat_map do |entry, index|
          next [ "controls row #{index + 1} must be an object" ] unless entry.respond_to?(:to_h) && !entry.is_a?(Array)

          entry = entry.to_h.transform_keys(&:to_s)
          problems = entry["action"].to_s.strip.empty? ? [ "controls row #{index + 1} has no action" ] : []
          problems + Array(entry["keys"]).map(&:to_s).reject { |key| key_known?(key) }
                                         .map { |key| "controls row #{index + 1}: #{key} is not a KeyboardEvent.code" }
        end
      end

      # Returns +true+ when +key+ is a <tt>KeyboardEvent.code</tt> or an alias.
      def key_known?(key) = ALIASES.include?(key) || CODE.match?(key)
    end
  end
end
