module WarpEngine
  # Serves the web player page of a release: the page template of the
  # runtime the release plays in, filled with the release's payload and the
  # binding's parameters (see WarpEngine::PlayService).
  class PlayController < ApiController
    # The headers that make a page cross-origin isolated, for a binding that
    # needs +SharedArrayBuffer+.
    ISOLATION_HEADERS = {
      "Cross-Origin-Opener-Policy" => "same-origin",
      "Cross-Origin-Embedder-Policy" => "require-corp"
    }.freeze

    # The hosts a preview payload URL may name: the loopback interface only.
    LOOPBACK_HOSTS = %w[127.0.0.1 localhost [::1] ::1].freeze

    resource_description do
      short "Web player"
      formats [ "html" ]
    end

    api :GET, "/play/:name/:version(/:binding)", "The web player page of a release"
    param :name, String, required: true, desc: "Software name"
    param :version, String, required: true, desc: "Release version"
    param :binding, String, required: false, desc: "A web binding key of the platform; the release's own when absent"
    returns code: 200, desc: "HTML page"
    error code: 403, desc: "The access policy refused the payload"
    error code: 404, desc: "The release does not play on the web (in that binding)"
    # <tt>GET /play/:name/:version(/:binding)</tt>.
    #
    # Renders the runtime's page as HTML, with the cross-origin isolation
    # headers when the binding needs them. Responds 404 when
    # WarpEngine::PlayService finds nothing to play and 403 when the access
    # policy refuses the payload.
    def show
      page = WarpEngine::PlayService.new.page(name: params[:name], version: params[:version],
                                              binding: params[:binding], subject: current_subject)
      response.headers.merge!(ISOLATION_HEADERS) if page.isolated?
      render html: WarpEngine::Runtime::Template.render(page.template, values(page)).html_safe
    rescue WarpEngine::PlayService::NotFound
      head :not_found
    end

    api :GET, "/play-preview/:platform(/:binding)", "A runtime page for a local build"
    param :platform, String, required: true, desc: "Platform name"
    param :binding, String, required: false, desc: "A web binding key of the platform; the default when absent"
    param :payload, String, required: true, desc: "The payload URL, on the loopback interface (http://127.0.0.1:PORT/...)"
    param :title, String, required: false, desc: "The page title"
    param :params, String, required: false, desc: "The runtime parameters as JSON (a metadata's web.params)"
    param :start, String, required: false, desc: "The program a launcher starts"
    returns code: 200, desc: "HTML page"
    error code: 400, desc: "The payload is not on the loopback interface"
    error code: 404, desc: "The platform does not play on the web (in that binding)"
    # <tt>GET /play-preview/:platform(/:binding)</tt>.
    #
    # Renders the runtime's page around a payload a developer's tool serves
    # on the loopback interface, so a local build plays in the runtime its
    # release would. Only a loopback +payload+ URL is taken, so the page
    # never plays someone else's file under the host's name. The page leaves
    # out +X-Frame-Options+, so an editor's panel can frame it. Responds 400 for
    # another URL or unreadable +params+, and 404 when
    # WarpEngine::PlayService#preview finds nothing to play in.
    def preview
      payload = loopback_url(params[:payload])
      return render plain: "payload must be a loopback URL", status: :bad_request if payload.nil?

      page = WarpEngine::PlayService.new.preview(platform: params[:platform], binding: params[:binding],
                                                 params: params[:params].present? ? JSON.parse(params[:params]) : nil)
      response.headers.merge!(ISOLATION_HEADERS) if page.isolated?
      response.headers.delete("X-Frame-Options")
      render html: WarpEngine::Runtime::Template.render(page.template, preview_values(page, payload)).html_safe
    rescue JSON::ParserError
      render plain: "params must be JSON", status: :bad_request
    rescue WarpEngine::PlayService::NotFound
      head :not_found
    end

    private

    def loopback_url(value)
      uri = URI.parse(value.to_s)
      uri if %w[http https].include?(uri.scheme) && LOOPBACK_HOSTS.include?(uri.host) && uri.userinfo.nil?
    rescue URI::InvalidURIError
      nil
    end

    def preview_values(page, payload)
      {
        "title" => params[:title].presence || "Preview",
        "name" => "preview",
        "version" => "local",
        "payload_url" => payload.to_s,
        "runtime_url" => "#{file_path(path: page.runtime_version.path)}/",
        "isolated" => page.isolated?,
        "params" => page.params,
        "start" => params[:start].presence
      }
    end

    def values(page)
      {
        "title" => page.software.title.presence || page.software.name,
        "name" => page.software.name,
        "version" => page.release.version,
        "payload_url" => file_path(path: page.payload_path),
        "runtime_url" => "#{file_path(path: page.runtime_version.path)}/",
        "isolated" => page.isolated?,
        "params" => page.params,
        "start" => page.release.web_options.to_h["start"]
      }
    end
  end
end
