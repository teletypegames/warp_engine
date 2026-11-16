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

    private

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
