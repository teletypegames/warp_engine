require "open3"
require "fileutils"
require "tmpdir"
require "json"

module WarpEngine
  module Sync
    module Transports
      # The +rsync+ transport: a file mirror over SSH. A package lands in
      # <tt><path>/<name>/<version>/</tt> on the other host, its files under the
      # names the CI uploaded them with, the metadata as
      # <tt><name>-<version>.metadata.json</tt> — the release layout of the
      # engine (WarpEngine::ReleaseLayout), without a catalog on the other side
      # (+publishes?+ is +false+).
      #
      # It runs the +rsync+ and +ssh+ programs of the host, which must be
      # installed. The private key (the peer's secret) and the host key live in
      # a temporary folder only while a command runs. Without a +host_key+ the
      # first connection takes the host's key (<tt>StrictHostKeyChecking
      # accept-new</tt>) for that command only; with one, only that key is
      # trusted.
      class Rsync < Transport
        # rsync exit statuses that mean the other side was not reached, so
        # the push is tried again: socket and protocol errors (10, 12), the
        # timeouts (30, 35) and an SSH failure (255).
        UNREACHABLE = [ 10, 12, 30, 35, 255 ].freeze

        # rsync exit statuses of a listing whose folder does not exist (yet):
        # partial transfer (23) and vanished source files (24).
        MISSING = [ 23, 24 ].freeze

        # Returns <tt>"rsync"</tt>.
        def self.key = "rsync"

        # Returns +true+: the images are mirrored too.
        def self.images? = true

        # Returns the human name.
        def self.label = "rsync (SSH)"

        # Returns the options: +host+, +user+, +path+ (the base folder there),
        # +port+, +host_key+ (a known_hosts line, optional) and the +ssh_key+
        # (secret, a private key).
        def self.options
          [ Option.new(name: "host", label: "Host", type: :string, required: true, secret: false,
                       hint: "The SSH host, e.g. mirror.example.org"),
            Option.new(name: "port", label: "Port", type: :string, required: false, secret: false, hint: "Default 22"),
            Option.new(name: "user", label: "User", type: :string, required: true, secret: false,
                       hint: "The SSH user that may write into the path"),
            Option.new(name: "path", label: "Path", type: :string, required: true, secret: false,
                       hint: "The base folder there; releases land in <path>/<name>/<version>/"),
            Option.new(name: "host_key", label: "Host key", type: :string, required: false, secret: false,
                       hint: "Its known_hosts line (ssh-keyscan). Empty: the key it shows first is taken"),
            Option.new(name: "ssh_key", label: "Private key", type: :text, required: true, secret: true,
                       hint: "The private key of the user (OpenSSH format, no passphrase)") ]
        end

        # Returns the error messages of +peer+: Transport.errors_for, and a
        # port that is no number.
        def self.errors_for(peer)
          errors = super
          port = peer.option("port").to_s
          errors << "Port must be a number" if port.present? && !port.match?(/\A\d{1,5}\z/)
          errors
        end

        # Lists the base folder. Returns a Transport::CheckResult: +ok+ when
        # the listing worked, the rsync exit status and its message otherwise.
        def check
          return CheckResult.new(ok: false, status: nil, version: nil, message: "the private key does not decrypt; enter it again") if secret.nil?

          status, _out, err = rsync([ "--list-only", "#{remote}/" ])
          return CheckResult.new(ok: true, status: 0, version: nil, message: "#{target} answers and takes the key") if status.zero?

          CheckResult.new(ok: false, status: status, version: nil, message: err.strip.lines.last.to_s.strip.presence || "rsync exited #{status}")
        rescue WarpEngine::Error => e
          CheckResult.new(ok: false, status: nil, version: nil, message: e.message)
        end

        # Lists <tt><path>/<name>/<version>/</tt> and returns the kinds of
        # +package+ whose files are there, an empty Array when the folder is
        # missing, or +nil+ when the listing fails otherwise.
        def existing(package)
          status, out, = rsync([ "--list-only", "#{remote}/#{package.name}/#{package.version}/" ])
          return [] if MISSING.include?(status)
          return nil unless status.zero?

          names = out.lines.filter_map { |line| line.split(/\s+/, 5)[4]&.strip }
          package.files.select { |file| file.kind && names.include?(file.name) }.map(&:kind)
        rescue WarpEngine::Error
          nil
        end

        # Copies the files of +package+ into a staging folder as
        # <tt><name>/<version>/<file></tt> and sends that tree under the base
        # folder (the folders are created, files there are replaced, others
        # are left alone). Yields the step <tt>upload:<name>/<version></tt>.
        # Returns a Transport::Delivery: +succeeded+, or +failed+ with rsync's
        # message (also when rsync is not installed). Raises
        # Transport::Unreachable when the host is not reached.
        def deliver(package)
          yield "upload:#{package.name}/#{package.version}" if block_given?
          Dir.mktmpdir("warp-engine-rsync") do |staging|
            folder = File.join(staging, package.name, package.version)
            FileUtils.mkdir_p(folder)
            package.files.each { |file| place(file.path, File.join(folder, file.name)) }
            status, _out, err = rsync([ "--recursive", "--times", "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r", "#{staging}/", "#{remote}/" ])
            return Delivery.new(status: "succeeded", code: 0, message: nil) if status.zero?

            Delivery.new(status: "failed", code: status, message: err.strip.lines.last.to_s.strip.presence || "rsync exited #{status}")
          end
        rescue Unreachable
          raise
        rescue WarpEngine::Error => e
          Delivery.new(status: "failed", code: nil, message: e.message)
        end

        # Mirrors the gallery of the software +name+ into
        # <tt><path>/<name>/images/</tt>: each of +images+ as
        # WarpEngine::Sync::ImageFile#mirror_name, and <tt>images.json</tt>
        # with the manifest; files no longer in the gallery are deleted there.
        # Returns a Transport::Delivery like #deliver. Raises Transport::Unreachable.
        def deliver_images(name, images)
          yield "images" if block_given?
          Dir.mktmpdir("warp-engine-rsync") do |staging|
            folder = File.join(staging, name, "images")
            FileUtils.mkdir_p(folder)
            manifest = images.each_with_index.map do |image, index|
              place(image.path, File.join(folder, image.mirror_name(index)))
              image.to_manifest.merge(file: image.mirror_name(index))
            end
            File.write(File.join(folder, "images.json"), JSON.pretty_generate(manifest))
            status, _out, err = rsync([ "--recursive", "--times", "--delete", "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r",
                                        "--include=/#{name}/", "--include=/#{name}/images/***", "--exclude=*",
                                        "#{staging}/", "#{remote}/" ])
            return Delivery.new(status: "succeeded", code: 0, message: nil) if status.zero?

            Delivery.new(status: "failed", code: status, message: err.strip.lines.last.to_s.strip.presence || "rsync exited #{status}")
          end
        rescue Unreachable
          raise
        rescue WarpEngine::Error => e
          Delivery.new(status: "failed", code: nil, message: e.message)
        end

        private

        def target = "#{option('user')}@#{option('host')}"

        def remote = "#{target}:#{option('path').to_s.chomp('/')}"

        def timeout = WarpEngine::Sync.config.outbound.timeout.to_i

        def place(source, destination)
          File.link(source, destination)
        rescue SystemCallError
          FileUtils.cp(source, destination)
        end

        def rsync(arguments)
          Dir.mktmpdir("warp-engine-ssh") do |dir|
            command = [ "rsync", "--protect-args", "--timeout=#{timeout}", "-e", ssh_command(dir), *arguments ]
            out, err, status = Open3.capture3(*command)
            code = status.exitstatus.to_i
            raise Unreachable, "#{option('host')}: #{err.strip.lines.last.to_s.strip.presence || "rsync exited #{code}"}" if UNREACHABLE.include?(code)

            [ code, out, err ]
          end
        rescue Errno::ENOENT
          raise WarpEngine::Error, "rsync is not installed on this host"
        end

        def ssh_command(dir)
          key = File.join(dir, "id")
          File.write(key, "#{secret.to_s.strip}\n")
          File.chmod(0o600, key)
          known_hosts = File.join(dir, "known_hosts")
          File.write(known_hosts, "#{option('host_key').to_s.strip}\n")
          checking = option("host_key").present? ? "yes" : "accept-new"
          [ "ssh", "-i", key, "-p", (option("port").presence || "22").to_s.to_i.to_s,
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=#{checking}", "-o", "UserKnownHostsFile=#{known_hosts}" ].join(" ")
        end
      end
    end
  end
end
