module WarpEngine
  class SoftwareDetailSerializer < Blueprinter::Base
    field(:software)           { |sw, _|    SoftwareSerializer.render_as_hash(sw) }
    field(:releases)           { |_, opts|  ReleaseSerializer.render_as_hash(opts[:releases], download_counts: opts[:download_counts]) }
    field(:latestRelease)      { |_, opts|  opts[:latest]       ? ReleaseSerializer.render_as_hash(opts[:latest], download_counts: opts[:download_counts])       : nil }
    field(:webPlayableRelease) { |_, opts|  opts[:web_playable] ? ReleaseSerializer.render_as_hash(opts[:web_playable], download_counts: opts[:download_counts]) : nil }
    field(:totalDownloads)     { |_, opts|  opts[:total_downloads] || 0 }
  end
end
