module WarpEngine
  # The names and texts written for machines with small, plain character
  # sets: a software's +shelf_name+, a shelf file name, an Assembly64 file
  # name, an index line. Shared by the models and every outlet type, so a
  # title reads the same everywhere.
  module Names
    # The characters a name may consist of: capitals, digits and dashes.
    PATTERN = /\A[A-Z0-9-]+\z/
    module_function
    # Returns +value+ as a name: transliterated to ASCII, upcased, every run
    # of other characters than <tt>A-Z 0-9 -</tt> turned into one dash,
    # leading and trailing dashes removed.
    def normalize(value)
      I18n.transliterate(value.to_s).upcase.gsub(/[^A-Z0-9-]+/, "-").squeeze("-").gsub(/\A-+|-+\z/, "")
    end
    # Returns +text+ as printable ASCII for a listing: transliterated, with
    # <tt>|</tt>, tabs and line breaks turned into spaces, other characters
    # dropped and spaces squeezed.
    def clean(text)
      I18n.transliterate(text.to_s).gsub(/[|\r\n\t]/, " ").gsub(/[^\x20-\x7E]/, "").squeeze(" ").strip
    end
    # Returns the file name of +software+: its +shelf_name+ or +name+,
    # normalized (#normalize), cut so that it fits +length+ characters with
    # +extension+, without trailing dashes, plus +extension+. Returns +nil+
    # when nothing of the name is left.
    #
    # [software]  a WarpEngine::Software
    # [length]    the longest name, extension included
    # [extension] the extension with its dot (<tt>.PRG</tt>), or the empty String
    def file_name(software, length:, extension: "")
      base = normalize(software.shelf_name.presence || software.name)
      base = base[0, [ length - extension.length, 0 ].max].sub(/-+\z/, "")
      base.empty? ? nil : "#{base}#{extension}"
    end
  end
end
