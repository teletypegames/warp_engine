module WarpEngine
  # A labelled link of a software to somewhere else (table +external_links+).
  # Needs a +label+ and a +url+. Soft-deletable.
  #
  # Its +kind+ is +link+ (a page) or +source+ (the git repository the software
  # is built from, at most one kept per software, cloned and forked by the
  # developer tools; +ref+ names a branch or tag, blank for the default
  # branch). A source carries the result of the anonymous reachability check
  # (WarpEngine::SourceVerifyService): +public+ (+true+, +false+, or +nil+
  # until checked), +verified_at+ and +verify_error+; changing its URL or ref
  # clears them.
  class ExternalLink < ApplicationRecord
    self.table_name = "external_links"

    include SoftDeletable

    # The kinds of a link.
    KINDS = %w[link source].freeze

    # The URL forms a source may take: https, http, ssh, git and the scp form
    # <tt>user@host:path</tt>.
    SOURCE_URL = %r{\A(?:(?:https?|ssh|git)://[^\s/]+/\S+|[\w.-]+@[\w.-]+:\S+)\z}

    belongs_to :software

    normalizes :ref, with: ->(value) { value.to_s.strip.presence }

    validates :label, presence: true
    validates :url, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :url, format: { with: SOURCE_URL, message: "is not a git address (https://, ssh:// or user@host:path)" }, if: :source?
    validate :one_source_per_software, if: -> { source? && deleted_at.nil? }

    before_save :clear_verification, if: -> { source? && (will_save_change_to_url? || will_save_change_to_ref? || will_save_change_to_kind?) }

    scope :sources, -> { where(kind: "source") }

    # Whether this link is the software's source repository.
    def source? = kind == "source"

    private

    def one_source_per_software
      others = self.class.kept.sources.where(software_id: software_id)
      others = others.where.not(id: id) if persisted?
      errors.add(:kind, "source is taken: a software has one source link") if others.exists?
    end

    def clear_verification
      self.public = nil
      self.verified_at = nil
      self.verify_error = nil
    end

    ActiveSupport.run_load_hooks(:warp_engine_external_link, self)
  end
end
