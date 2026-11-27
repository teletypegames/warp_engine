module WarpEngine
  # One kind of release asset and how it travels from the CI to the file
  # container: the upload is <tt><name>-<version></tt> plus +suffix+ (+nil+ when
  # the platform supplies the extension, as for +package+ and +source+). A
  # kind with an +unpack_to+ is a zip the engine unpacks into a folder named
  # after the kind in the release's folder (WarpEngine::ReleaseLayout), which
  # then is the asset; +unpack_to+ is what followed <tt><name>-<version></tt>
  # in that folder's name in the flat layout before 3.4. A kind with
  # +launch+ +false+ is only downloaded: a client installs it but never starts
  # it (a command-line program's archive); the catalog says so on its assets.
  #
  #   WarpEngine::AssetKinds.fetch("docs").upload_name("game-1.0") # => "game-1.0-docs.zip"
  #   WarpEngine::AssetKinds.fetch("docs").asset_name("game-1.0")  # => "docs"
  AssetKind = ::Data.define(:name, :suffix, :unpack_to, :launch) do
    # Builds a kind; +launch+ defaults to +true+.
    def initialize(name:, suffix:, unpack_to:, launch: true) = super

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

    # Returns the name of the asset in the release's folder: the unpacked
    # folder (the kind name), or the upload itself.
    def asset_name(versioned, ext: nil) = unpacked? ? name : upload_name(versioned, ext: ext)

    # Returns +true+ when a client may start the asset (see +launch+).
    def launchable? = launch
  end

  # The registry of every AssetKind, in the order the catalog lists them.
  #
  # The one place old kind names are read: every way a kind comes in (the CI
  # upload and publish, the platform and config DSL, the Admin API, the
  # +kind+ filters, a sync peer) goes through #canonical, so
  # <tt>cartridge</tt> is read as +package+. The engine only ever writes the
  # new names.
  module AssetKinds
    # Every asset kind, by name.
    ALL = [
      AssetKind.new("package",     nil,                  nil),
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
      AssetKind.new("mac_universal", "-mac-universal.zip", nil),
      AssetKind.new("cli_win_x64",     "-win-x64-cli.zip",     nil, false),
      AssetKind.new("cli_linux_x64",   "-linux-x64-cli.zip",   nil, false),
      AssetKind.new("cli_linux_arm64", "-linux-arm64-cli.zip", nil, false),
      AssetKind.new("cli_mac_x64",     "-mac-x64-cli.zip",     nil, false),
      AssetKind.new("cli_mac_arm64",   "-mac-arm64-cli.zip",   nil, false)
    ].index_by(&:name).freeze

    # The old kind names a caller may still send, with the kind each is read as.
    ALIASES = { "cartridge" => "package" }.freeze

    # Returns the name +name+ stands for: its ALIASES entry, or +name+ as a
    # String. An unknown name is returned as it is, for the caller to reject.
    def self.canonical(name) = ALIASES.fetch(name.to_s, name.to_s)

    # Returns the names in +names+ (an Array or a single name) through
    # #canonical, without duplicates.
    def self.canonical_list(names) = Array(names).map { |name| canonical(name) }.uniq

    # Returns the AssetKind named +name+ (an alias included, see #canonical).
    # Raises KeyError for an unknown one.
    def self.fetch(name) = ALL.fetch(canonical(name))

    # Returns the kind names, in order.
    def self.names = ALL.keys

    # Returns +true+ when a client may start an asset of the kind +name+; an
    # unknown kind counts as launchable, as before the +launch+ flag.
    def self.launchable?(name) = ALL[name.to_s]&.launchable? != false
  end
end
