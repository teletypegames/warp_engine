module WarpEngine
  # A software with its releases, as <tt>GET /api/software/highlighted</tt>
  # returns it: +software+ (SoftwareSerializer), +releases+, +latestRelease+
  # and +webPlayableRelease+ (ReleaseSerializer), +totalDownloads+ and
  # +access+. The releases, counts and access come from the render options
  # +releases+, +latest+, +web_playable+, +download_counts+,
  # +total_downloads+ and +access+ (WarpEngine::Access::OPEN when absent).
  class SoftwareDetailSerializer < Blueprinter::Base
    field(:software)           { |sw, _|    SoftwareSerializer.render_as_hash(sw) }
    field(:releases)           { |_, opts|  ReleaseSerializer.render_as_hash(opts[:releases], download_counts: opts[:download_counts]) }
    field(:latestRelease)      { |_, opts|  opts[:latest]       ? ReleaseSerializer.render_as_hash(opts[:latest], download_counts: opts[:download_counts])       : nil }
    field(:webPlayableRelease) { |_, opts|  opts[:web_playable] ? ReleaseSerializer.render_as_hash(opts[:web_playable], download_counts: opts[:download_counts]) : nil }
    field(:totalDownloads)     { |_, opts|  opts[:total_downloads] || 0 }

    field(:access)             { |_, opts| (opts[:access] || WarpEngine::Access::OPEN).as_json }
  end
end
