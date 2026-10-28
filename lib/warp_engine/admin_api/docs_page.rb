module WarpEngine
  module AdminApi
    # The Redoc HTML page of the OpenAPI document, served when Configuration#docs_ui is on.
    module DocsPage
      # The Redoc standalone bundle the page loads.
      REDOC = "https://cdn.jsdelivr.net/npm/redoc@2/bundles/redoc.standalone.js".freeze

      module_function

      # Returns the HTML page rendering the OpenAPI +document+ (a hash) with Redoc.
      def render(document)
        spec = ERB::Util.json_escape(document.to_json)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>WarpEngine Admin API</title>
          </head>
          <body>
            <div id="redoc"></div>
            <script src="#{REDOC}"></script>
            <script>Redoc.init(#{spec}, {}, document.getElementById("redoc"));</script>
          </body>
          </html>
        HTML
      end
    end
  end
end
