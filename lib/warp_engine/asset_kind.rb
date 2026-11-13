module WarpEngine
  # One kind of release asset and how it travels from the CI to the file
  # container: the upload is <tt><name>-<version></tt> plus +suffix+ (+nil+ when
  # the platform supplies the extension, as for +cartridge+ and +source+), and
  # an +unpack_to+ suffix marks a zip the engine unpacks into a directory
  # (<tt><name>-<version><unpack_to></tt>), which then is the asset.
  #
  #   WarpEngine::AssetKinds.fetch("docs").upload_name("game-1.0") # => "game-1.0-docs.zip"
  #   WarpEngine::AssetKinds.fetch("docs").asset_name("game-1.0")  # => "game-1.0-docs"
  AssetKind = ::Data.define(:name, :suffix, :unpack_to) do
    # Returns the uploaded file name of the kind for +versioned+
    # (<tt>name-version</tt>). +ext+ is the extension of a kind without a
    # suffix. Raises ArgumentError when such a kind gets no +ext+.
    def upload_name(versioned, ext: nil)
      tail = suffix || ext
      raise ArgumentError, "the #{name} kind needs an extension" if tail.blank?

      "#{versioned}#{tail}"
    end

    # Returns +true+ when the upload is a zip the engine unpacks.
    def unpacked? = !unpack_to.nil?

    # Returns the name of the asset in the file container: the unpacked
    # directory, or the upload itself.
    def asset_name(versioned, ext: nil) = unpacked? ? "#{versioned}#{unpack_to}" : upload_name(versioned, ext: ext)
  end

  # The registry of every AssetKind, in the order the catalog lists them.
  module AssetKinds
    # Every asset kind, by name.
    ALL = [
      AssetKind.new("cartridge",     nil,                  nil),
      AssetKind.new("source",        nil,                  nil),
      AssetKind.new("html",          ".html.zip",          ""),
      AssetKind.new("docs",          "-docs.zip",          "-docs"),
      AssetKind.new("win_x86",       "-win-x86.zip",       nil),
      AssetKind.new("win_x64",       "-win-x64.zip",       nil),
      AssetKind.new("linux_x86",     "-linux-x86.zip",     nil),
      AssetKind.new("linux_x64",     "-linux-x64.zip",     nil),
      AssetKind.new("linux_arm64",   "-linux-arm64.zip",   nil),
      AssetKind.new("mac_x64",       "-mac-x64.zip",       nil),
      AssetKind.new("mac_arm64",     "-mac-arm64.zip",     nil),
      AssetKind.new("mac_universal", "-mac-universal.zip", nil)
    ].index_by(&:name).freeze

    # Returns the AssetKind named +name+. Raises KeyError for an unknown one.
    def self.fetch(name) = ALL.fetch(name.to_s)

    # Returns the kind names, in order.
    def self.names = ALL.keys
  end
end
