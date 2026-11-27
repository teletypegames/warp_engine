module WarpEngine
  # Tells the open pull request of a development build's branch where the
  # build plays and downloads: one comment per pull request, written by the
  # SCM (WarpEngine.scm) and changed on every later build of the branch.
  # Runs after the publish of a development build (warp_engine.publish), when
  # an SCM is configured and the software's CI repository names its git repository.
  class PreviewCommentJob < ApplicationJob
    queue_as :default

    # The marker that finds the comment again on the next build.
    MARKER = "<!-- warpengine-preview -->".freeze

    # Comments on the pull request of the branch of release +release_id+.
    # Does nothing for a release that is no development build, has no branch,
    # no CI repository or no open pull request; an SCM error is logged, not raised.
    def perform(release_id)
      release = WarpEngine::Release.kept.find_by(id: release_id)
      return unless release&.dev? && release.branch

      repository = release.software&.ci_repository
      return if repository.nil? || !WarpEngine.scm.configured?

      number = WarpEngine.scm.open_pull_request(owner: repository.repo_owner, name: repository.repo_name, branch: release.branch)
      return if number.nil?

      WarpEngine.scm.upsert_comment(owner: repository.repo_owner, name: repository.repo_name, number: number,
                                      marker: MARKER, body: self.class.body(release))
    rescue WarpEngine::Scm::Error => e
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
