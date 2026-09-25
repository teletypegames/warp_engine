module WarpEngine
  module AdminApi
    module Definitions
      module Statistics
        S = AdminApi::Schema
        X = Schemas

        module_function

        def define(api)
          api.resource(:downloads, label: "Downloads") do |r|
            r.list "/downloads", summary: "The download log", item: X.download,
                   filters: {
                     filePath:  S.string("File path contains"),
                     software:  S.string("Software title contains"),
                     ipAddress: S.string("IP address contains"),
                     userAgent: S.string("User-Agent contains"),
                     referer:   S.string("Referer contains"),
                     from:      S.datetime("Downloaded at or after"),
                     to:        S.datetime("Downloaded before")
                   },
                   sort: { createdAt: :created_at }, default_sort: "-createdAt" do |ctx|
              ctx.list(filtered(ctx), Admin::DownloadSerializer)
            end

            r.action :get, "/downloads/summary", name: :summary, summary: "Downloads in total, today, this week, this month",
                     item: X.download_summary do |ctx|
              ctx.ok(camelize(service.summary))
            end

            r.action :get, "/downloads/top_files", name: :top_files, summary: "The most downloaded files",
                     item: X.file_downloads, many: true,
                     query: { limit: S.integer("How many; 10 by default, 100 at most", minimum: 1) } do |ctx|
              ctx.ok(camelize(service.top_files(limit: limit(ctx, 10))))
            end

            r.action :get, "/downloads/top_softwares", name: :top_softwares, summary: "The most downloaded softwares",
                     item: X.software_downloads, many: true,
                     query: { limit: S.integer("How many; 5 by default, 100 at most", minimum: 1) } do |ctx|
              ctx.ok(camelize(service.top_softwares(limit: limit(ctx, 5))))
            end

            r.action :get, "/softwares/:id/download_stats", name: :software_stats,
                     summary: "Downloads of one software, by release and by file",
                     item: X.software_download_stats do |ctx|
              ctx.ok(camelize(service.for_software(WarpEngine::Software.kept.find(ctx.id))))
            end

            r.get "/downloads/:id", summary: "One download", item: X.download do |ctx|
              ctx.ok(Admin::DownloadSerializer.render_as_hash(WarpEngine::Download.kept.find(ctx.id)))
            end
          end
        end

        def filtered(ctx)
          scope = WarpEngine::Download.kept.includes(:release)
          { filePath: :file_path, ipAddress: :ip_address, userAgent: :user_agent, referer: :referer }.each do |param, column|
            scope = scope.where("downloads.#{column} LIKE ?", like(ctx[param])) if ctx[param].present?
          end
          if ctx[:software].present?
            scope = scope.joins(release: :software).where("softwares.title LIKE ?", like(ctx[:software]))
          end
          scope = scope.where(created_at: time(ctx[:from], :from)..) if ctx[:from].present?
          scope = scope.where(created_at: ...time(ctx[:to], :to)) if ctx[:to].present?
          scope
        end

        def service = WarpEngine::DownloadStatsService.new

        def limit(ctx, default)
          (ctx[:limit] || default).to_i.clamp(1, 100)
        end

        def time(value, name)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          raise Error.bad_request("#{name} must be an ISO 8601 time")
        end

        def camelize(value)
          case value
          when Hash  then value.to_h { |key, item| [ key.to_s.camelize(:lower), camelize(item) ] }
          when Array then value.map { |item| camelize(item) }
          else value
          end
        end

        def like(value)
          "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
        end
      end
    end
  end
end
