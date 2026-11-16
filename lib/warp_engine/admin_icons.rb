require "erb"

module WarpEngine
  # The icons of the engine's admin pages: stroke icons in the style of
  # Lucide (24 px grid, round caps), drawn as inline SVG in +currentColor+, so
  # they take the text color of the theme around them. The pages use no
  # emoji.
  #
  #   WarpEngine::AdminIcons.svg(:folder)                  # decorative
  #   WarpEngine::AdminIcons.svg(:trash, label: "Delete")  # announced
  module AdminIcons
    # The path data of every icon by name; an icon of several strokes lists
    # them separated by <tt>|</tt>.
    PATHS = {
      ok: "M20 6 9 17l-5-5",
      warn: "M12 9v4|M12 17h.01|M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z",
      error: "M18 6 6 18|M6 6l12 12",
      off: "M5 12h14",
      info: "M12 16v-4|M12 8h.01|M12 2a10 10 0 1 0 0 20 10 10 0 1 0 0-20z",
      chevron: "m9 18 6-6-6-6",
      search: "M21 21l-4.3-4.3|M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z",
      expand: "m7 15 5 5 5-5|M7 9l5-5 5 5",
      collapse: "m7 20 5-5 5 5|M7 4l5 5 5-5",
      refresh: "M21 12a9 9 0 1 1-3-6.7L21 8|M21 3v5h-5",
      engine: "M6 4h12v16H6z|M9 9h6v6H9z|M9 1v3|M15 1v3|M9 20v3|M15 20v3|M1 9h3|M1 15h3|M20 9h3|M20 15h3",
      key: "M15.5 7.5 19 4l3 3-3.5 3.5|M11.4 11.6a5.5 5.5 0 1 1-7.8 7.8 5.5 5.5 0 0 1 7.8-7.8z|M11.4 11.6 15.5 7.5",
      plug: "M12 22v-5|M9 8V2|M15 8V2|M18 8v5a6 6 0 0 1-12 0V8z",
      user: "M20 21a8 8 0 0 0-16 0|M12 13a5 5 0 1 0 0-10 5 5 0 0 0 0 10z",
      branch: "M6 3v12|M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z|M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z|M18 9a9 9 0 0 1-9 9",
      gamepad: "M6 12h4|M8 10v4|M15 13h.01|M18 11h.01|M17.3 5H6.7a4 4 0 0 0-4 3.6L2 15a3 3 0 0 0 5.2 2.2L9 15h6l1.8 2.2A3 3 0 0 0 22 15l-.7-6.4A4 4 0 0 0 17.3 5z",
      send: "M22 2 11 13|M22 2l-7 20-4-9-9-4 20-7z",
      terminal: "M4 17l6-6-6-6|M12 19h8",
      plus: "M12 8v8|M8 12h8|M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z",
      folder: "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z",
      file: "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z|M14 2v4a2 2 0 0 0 2 2h4",
      file_text: "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z|M14 2v4a2 2 0 0 0 2 2h4|M10 9H8|M16 13H8|M16 17H8",
      file_code: "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z|M14 2v4a2 2 0 0 0 2 2h4|m10 13-2 2 2 2|m14 17 2-2-2-2",
      image: "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z|M9 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4z|m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21",
      music: "M9 18V5l12-2v13|M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z|M18 19a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
      film: "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z|M7 3v18|M17 3v18|M3 7.5h4|M3 12h18|M3 16.5h4|M17 7.5h4|M17 16.5h4",
      archive: "M21 8v13H3V8|M1 3h22v5H1z|M10 12h4",
      sheet: "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z|M3 9h18|M3 15h18|M9 9v12|M15 9v12",
      code: "m16 18 6-6-6-6|m8 6-6 6 6 6",
      cog: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z|M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z",
      download: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4|M7 10l5 5 5-5|M12 15V3",
      pencil: "M21.2 6.8a1 1 0 0 0-4-4L3.8 16.2a2 2 0 0 0-.5.8L2 21.4a.5.5 0 0 0 .6.6L7 20.7a2 2 0 0 0 .8-.5z|m15 5 4 4",
      trash: "M3 6h18|M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6|M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2|M10 11v6|M14 11v6",
      chart: "M3 3v18h18|M18 17V9|M13 17V5|M8 17v-3",
      globe: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z|M2 12h20|M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
      eye: "M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z|M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
      external: "M15 3h6v6|M10 14 21 3|M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6",
      upload: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4|m17 8-5-5-5 5|M12 3v12"
    }.freeze

    module_function

    # Returns the icon +name+ (a key of PATHS) as an html_safe inline
    # <tt><svg></tt> of +size+ pixels drawn in +currentColor+. With +label+
    # it is announced as an image of that name; without, it is hidden from
    # assistive technology as decoration. Raises KeyError for an unknown name.
    #
    # [name]       the icon
    # [size]       width and height in pixels (default 16)
    # [label]      the accessible name, or +nil+ for a decorative icon
    # [css_class]  extra classes on the <tt><svg></tt>
    # [stroke]     the stroke width (default 2)
    def svg(name, size: 16, label: nil, css_class: nil, stroke: 2)
      paths = PATHS.fetch(name.to_sym).split("|").map { |d| %(<path d="#{d}"></path>) }.join
      a11y = label ? %(role="img" aria-label="#{ERB::Util.html_escape(label)}") : %(aria-hidden="true")
      klass = [ "we-icon", css_class ].compact.join(" ")
      markup = %(<svg class="#{klass}" width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" ) +
               %(stroke-width="#{stroke}" stroke-linecap="round" stroke-linejoin="round" #{a11y}>#{paths}</svg>)
      markup.html_safe
    end
  end
end
