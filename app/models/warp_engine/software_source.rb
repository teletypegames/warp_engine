module WarpEngine
  # The git repository a software is built from (table +software_sources+),
  # one per software, cloned and forked by the developer tools: its +url+
  # (https, http, ssh, git or the scp form) and the +ref+ (a branch or tag,
  # blank for the default branch). Carries the result of the anonymous
  # reachability check (WarpEngine::SourceVerifyService): +public+ (+true+,
  # +false+, or +nil+ until checked), +verified_at+ and +verify_error+;
  # changing the URL or the ref clears them. Soft-deletable; a software's
  # source is revived rather than made again.
  class SoftwareSource < ApplicationRecord
    self.table_name = "software_sources"

    include SoftDeletable

    # The URL forms a source may take: https, http, ssh, git and the scp form
    # <tt>user@host:path</tt>.
    URL_FORMAT = %r{\A(?:(?:https?|ssh|git)://[^\s/]+/\S+|[\w.-]+@[\w.-]+:\S+)\z}

    belongs_to :software

    normalizes :ref, with: ->(value) { value.to_s.strip.presence }

    validates :url, presence: true
    validates :url, format: { with: URL_FORMAT, message: "is not a git address (https://, ssh:// or user@host:path)" }, allow_blank: true
    validates :software_id, uniqueness: { conditions: -> { kept }, message: "has a source already: a software has one" },
                            if: -> { deleted_at.nil? }

    before_save :clear_verification, if: -> { will_save_change_to_url? || will_save_change_to_ref? }

    # Returns the source of +software+: the kept one, else the latest
    # soft-deleted one brought back in memory (not saved), else a new one.
    def self.for(software)
      kept.find_by(software_id: software.id) ||
        where(software_id: software.id).order(deleted_at: :desc).first&.tap { |source| source.deleted_at = nil } ||
        new(software: software)
    end

    private

    def clear_verification
      self.public = nil
      self.verified_at = nil
      self.verify_error = nil
    end

    ActiveSupport.run_load_hooks(:warp_engine_software_source, self)
  end
end
