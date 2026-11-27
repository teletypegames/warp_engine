module WarpEngine
  # The icon of an entry of the admin's file browser, chosen by file
  # extension: a WarpEngine::AdminIcons name.
  module FileIcon
    # Icon per group of lower-case extensions (with the leading dot): images,
    # audio, video, archives, documents, spreadsheets, web files, source
    # code, cartridge and disk images, and executables.
    BY_EXTENSION = {
      %w[.png .jpg .jpeg .gif .bmp .webp .svg]             => :image,
      %w[.mp3 .ogg .wav .flac .aac]                        => :music,
      %w[.mp4 .avi .mkv .webm .mov]                        => :film,
      %w[.zip .gz .tar .rar .7z .bz2]                      => :archive,
      %w[.pdf .doc .docx .odt .txt .md .rtf]               => :file_text,
      %w[.xls .xlsx .csv .ods]                             => :sheet,
      %w[.html .htm .css .js .ts .json .xml]               => :file_code,
      %w[.rb .py .lua .c .cpp .h .rs .go]                  => :code,
      %w[.tic .rom .bin .prg .crt .d64 .t64 .love]         => :gamepad,
      %w[.exe .dmg .appimage .msi .wasm]                   => :cog
    }.freeze

    # Icon of a file whose extension is in no group.
    DEFAULT   = :file
    # Icon of a folder.
    DIRECTORY = :folder

    # Returns the icon name for the file +name+ by its extension (case does
    # not matter), or DEFAULT.
    def self.for(name)
      ext = File.extname(name.to_s).downcase
      BY_EXTENSION.each { |extensions, icon| return icon if extensions.include?(ext) }
      DEFAULT
    end

    # Returns the icon of +name+ (DIRECTORY when +directory+) as inline SVG
    # (WarpEngine::AdminIcons.svg).
    def self.svg(name, directory: false) = AdminIcons.svg(directory ? DIRECTORY : self.for(name), css_class: "fm-file-icon")
  end
end
