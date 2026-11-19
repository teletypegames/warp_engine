require "socket"
require "json"
require "erb"
require "timeout"
require "digest"

module WarpEngine
  module Local
    class Runtime
      # The Docker Engine API on its unix socket (Docker Desktop, OrbStack,
      # Docker Engine; Podman answers the same API). Every container it
      # creates carries WarpEngine::Local::LABEL, and it stops or removes no
      # container without it.
      class Docker < Runtime
        # The label holding a digest of the ContainerSpec a container was made from.
        SPEC_LABEL = "#{LABEL}.spec".freeze
        # One answer of the Docker Engine API: the HTTP +status+ and the +body+.
        Response = ::Data.define(:status, :body) do
          # Whether the status is 2xx.
          def success? = status.between?(200, 299)

          # Returns the body parsed as JSON, or an empty Hash.
          def json
            parsed = JSON.parse(body)
            parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : {}
          rescue JSON::ParserError
            {}
          end

          # Returns the API's +message+, else <tt>HTTP <status></tt>.
          def message = (json.is_a?(Hash) && json["message"].presence) || "HTTP #{status}"
        end

        # [socket]  the path of the Docker Engine socket
        # [timeout] seconds one call may take (an image pull more)
        def initialize(socket:, timeout: 60)
          super()
          @socket = socket
          @timeout = timeout
        end

        # Returns +true+ when the socket is there.
        def available? = File.socket?(@socket)

        # Returns why there is no runtime, or +nil+.
        def unavailable_reason
          available? ? nil : "no Docker socket at #{@socket}: install the engine with the Docker socket (warp-engine-local 1.2 or later)"
        end

        # Creates the network +name+ unless it exists.
        def ensure_network(name)
          return if call(:get, "/networks/#{escape(name)}").success?

          check!(call(:post, "/networks/create", { Name: name, Labels: { LABEL => "1" } }), "create the network #{name}")
        end

        # Pulls +image+ unless it is here. Raises Runtime::Error when the pull fails.
        def pull(image)
          return if call(:get, "/images/#{escape(image)}/json").success?

          repository, tag = image.split(/:(?=[^:\/]+\z)/, 2)
          response = call(:post, "/images/create?fromImage=#{escape(repository)}&tag=#{escape(tag || 'latest')}", nil, timeout: 1800)
          check!(response, "pull #{image}")
          failure = response.body.lines.filter_map { |line| JSON.parse(line)["error"] rescue nil }.first
          raise Error, "pull #{image}: #{failure}" if failure
        end

        # Starts the container of +spec+ on +network+ (see Runtime#run); a
        # container made from another spec (SPEC_LABEL) is replaced.
        def run(spec, network:)
          current = inspect_container(spec.name)
          if current && current.dig("Config", "Labels", SPEC_LABEL) != digest(spec)
            remove(spec.name)
            current = nil
          end
          create(spec, network) unless current
          return if current&.dig("State", "Running")

          check!(call(:post, "/containers/#{escape(spec.name)}/start"), "start #{spec.name}")
        end

        # Returns the state of the container +name+, or +nil+.
        def state(name) = inspect_container(name)&.dig("State", "Status")

        # Stops the container +name+ when it runs and is ours.
        def stop(name)
          return unless ours?(name)

          call(:post, "/containers/#{escape(name)}/stop?t=10", nil, timeout: 30)
        end

        # Removes the container +name+ when it is ours (its volumes stay).
        def remove(name)
          return unless ours?(name)

          call(:delete, "/containers/#{escape(name)}?force=true")
        end

        # Removes the volume +name+ when it is ours.
        def remove_volume(name)
          volume = call(:get, "/volumes/#{escape(name)}")
          return unless volume.success? && volume.json.dig("Labels", LABEL)

          call(:delete, "/volumes/#{escape(name)}")
        end

        # Runs +cmd+ in the container +name+ as +user+. Returns <tt>[exit_code, output]</tt>.
        def exec(name, cmd, user: nil)
          created = call(:post, "/containers/#{escape(name)}/exec",
                         { Cmd: cmd, User: user.to_s, AttachStdout: true, AttachStderr: true })
          check!(created, "exec in #{name}")
          id = created.json["Id"]
          output = call(:post, "/exec/#{id}/start", { Detach: false, Tty: false }, timeout: 120).body
          [ call(:get, "/exec/#{id}/json").json["ExitCode"].to_i, demultiplex(output) ]
        end

        # Sends one request to the Docker Engine API and returns a Response.
        # Raises Runtime::Error when the socket does not answer in time.
        def call(method, path, body = nil, timeout: @timeout)
          raise Error, unavailable_reason unless available?

          payload = body.nil? ? "" : JSON.generate(body)
          Timeout.timeout(timeout) do
            UNIXSocket.open(@socket) do |io|
              io.write(request_text(method, path, payload))
              parse(io.read)
            end
          end
        rescue Timeout::Error
          raise Error, "the Docker Engine did not answer #{method.upcase} #{path} in #{timeout}s"
        rescue SystemCallError, IOError => e
          raise Error, "the Docker Engine is not reachable: #{e.message}"
        end

        private

        def create(spec, network)
          volumes = spec.volumes.map do |volume, path|
            call(:post, "/volumes/create", { Name: volume, Labels: { LABEL => "1" } })
            "#{volume}:#{path}"
          end
          body = {
            Image: spec.image, Env: spec.env.map { |key, value| "#{key}=#{value}" }, Labels: { LABEL => "1", SPEC_LABEL => digest(spec) },
            ExposedPorts: spec.ports.values.to_h { |port| [ "#{port}/tcp", {} ] },
            HostConfig: {
              Binds: volumes + spec.binds, RestartPolicy: { Name: "unless-stopped" },
              PortBindings: spec.ports.to_h { |host, port| [ "#{port}/tcp", [ { HostIp: "127.0.0.1", HostPort: host.to_s } ] ] }
            },
            NetworkingConfig: { EndpointsConfig: { network => { Aliases: [ spec.name, *spec.aliases ] } } }
          }
          body[:Cmd] = spec.cmd if spec.cmd
          body[:User] = spec.user if spec.user
          check!(call(:post, "/containers/create?name=#{escape(spec.name)}", body), "create #{spec.name}")
        end

        def digest(spec) = Digest::SHA256.hexdigest(JSON.generate(spec.to_h))[0, 16]

        def inspect_container(name)
          response = call(:get, "/containers/#{escape(name)}/json")
          response.success? ? response.json : nil
        end

        def ours?(name) = inspect_container(name)&.dig("Config", "Labels", LABEL).present?

        def check!(response, what)
          raise Error, "#{what}: #{response.message}" unless response.success?

          response
        end

        def escape(value) = ERB::Util.url_encode(value.to_s)

        def request_text(method, path, payload)
          head = [ "#{method.to_s.upcase} #{path} HTTP/1.1", "Host: docker", "Connection: close" ]
          head += [ "Content-Type: application/json", "Content-Length: #{payload.bytesize}" ] unless payload.empty? && method == :get
          "#{head.join("\r\n")}\r\n\r\n#{payload}"
        end

        def parse(raw)
          head, body = raw.to_s.b.split("\r\n\r\n", 2)
          lines = head.to_s.split("\r\n")
          status = lines.first.to_s.split(" ")[1].to_i
          chunked = lines.any? { |line| line.downcase.start_with?("transfer-encoding:") && line.downcase.include?("chunked") }
          Response.new(status: status, body: chunked ? dechunk(body.to_s) : body.to_s)
        end

        def dechunk(body)
          out = +""
          rest = body
          loop do
            size_line, rest = rest.split("\r\n", 2)
            size = size_line.to_s.to_i(16)
            break if size.zero? || rest.nil?

            out << rest.byteslice(0, size)
            rest = rest.byteslice(size + 2, rest.bytesize).to_s
          end
          out
        end

        def demultiplex(stream)
          out = +""
          data = stream.b
          while data.bytesize >= 8 && [ 1, 2 ].include?(data.getbyte(0))
            size = data.byteslice(4, 4).unpack1("N")
            out << data.byteslice(8, size).to_s
            data = data.byteslice(8 + size, data.bytesize).to_s
          end
          out.empty? ? stream : out.force_encoding(Encoding::UTF_8)
        end
      end
    end
  end
end
