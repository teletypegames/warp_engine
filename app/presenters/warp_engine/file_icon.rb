module WarpEngine
  # Emoji icons for the file browser of the admin, chosen by file extension.
  module FileIcon
    # Icon per group of lower-case extensions (with the leading dot): images,
    # audio, video, archives, PDF, documents, spreadsheets, web files, source
    # code, cartridges and disk images, and executables.
    BY_EXTENSION = {
      %w[.png .jpg .jpeg .gif .bmp .webp .svg]             => "🖼️",
      %w[.mp3 .ogg .wav .flac .aac]                        => "🔊",
      %w[.mp4 .avi .mkv .webm .mov]                        => "🎬",
      %w[.zip .gz .tar .rar .7z .bz2]                      => "📦",
      %w[.pdf]                                             => "📕",
      %w[.doc .docx .odt .txt .md .rtf]                    => "📄",
      %w[.xls .xlsx .csv .ods]                             => "📊",
      %w[.html .htm .css .js .ts .json .xml]               => "📝",
      %w[.rb .py .lua .c .cpp .h .rs .go]                  => "💻",
      %w[.tic .rom .bin .prg .crt .d64 .t64 .love]         => "🎮",
      %w[.exe .dmg .appimage .msi .wasm]                   => "⚙️"
    }.freeze

    # Icon of a file whose extension is in no group.
    DEFAULT   = "📄".freeze
    # Icon of a folder.
    DIRECTORY = "📁".freeze

    # Returns the icon for the file +name+ by its extension (case does not
    # matter), or DEFAULT.
    def self.for(name)
      ext = File.extname(name.to_s).downcase
      BY_EXTENSION.each { |extensions, icon| return icon if extensions.include?(ext) }
      DEFAULT
    end
  end
end
