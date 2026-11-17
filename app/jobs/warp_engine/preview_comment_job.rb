module WarpEngine
  # Tells the open pull request of a development build's branch where the
  # build plays and downloads: one comment per pull request, written by the
  # forge (WarpEngine.forge) and changed on every later build of the branch.
  # Runs after the publish of a development build (warp_engine.publish), when
  # a forge is configured and the software's pipeline names its repository.
  class PreviewCommentJob < ApplicationJob
    queue_as :default

    # The marker that finds the comment again on the next build.
    MARKER = "<!-- warpengine-preview -->".freeze

    # Comments on the pull request of the branch of release +release_id+.
    # Does nothing for a release that is no development build, has no branch,
    # no pipeline or no open pull request; a forge error is logged, not raised.
    def perform(release_id)
      release = WarpEngine::Release.kept.find_by(id: release_id)
      return unless release&.dev? && release.branch

      pipeline = release.software&.pipeline
      return if pipeline.nil? || !WarpEngine.forge.configured?

      number = WarpEngine.forge.open_pull_request(owner: pipeline.repo_owner, name: pipeline.repo_name, branch: release.branch)
      return if number.nil?

      WarpEngine.forge.upsert_comment(owner: pipeline.repo_owner, name: pipeline.repo_name, number: number,
                                      marker: MARKER, body: self.class.body(release))
    rescue WarpEngine::Forge::Error => e
      Rails.logger.warn("[WarpEngine::PreviewCommentJob] #{release&.software&.name} #{release&.version}: #{e.message}")
    end

    # Returns the comment text of +release+: the version and commit, the play
    # link when it plays on the web, and the download link of every asset, as
    # absolute URLs on <tt>WarpEngine.config.site_url</tt>.
    def self.body(release)
      site = WarpEngine.config.site_url.to_s.chomp("/")
      play = ReleaseSerializer.play_url(release)
      commit = release.commit_sha.present? ? " (commit `#{release.commit_sha.first(7)}`)" : ""
      lines = [ "**#{release.software.title}** `#{release.version}`#{commit} is built and published for this branch.", "" ]
      lines << "- [Play it in the browser](#{site}#{play})" if play.present?
      release.release_assets.sort_by(&:kind).each do |asset|
        path = ReleaseSerializer.asset_path(release, asset.kind)
        lines << "- #{asset.kind}: [#{File.basename(path.to_s.chomp('/'))}](#{site}#{path})" if path.present?
      end
      lines << "" << "_WarpEngine updates this comment on every build of the branch._"
      lines.join("\n")
    end
  end
end
