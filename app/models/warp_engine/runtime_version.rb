module WarpEngine
  # An installed version of a WarpEngine::Runtime: its files under
  # +path+ (<tt>_runtimes/<name>-<version></tt> of the file container), each
  # with its SHA-256 in +files+, and the components installed in it. Releases
  # bound to it (+runtime_version_id+) play in exactly this version. Written
  # by WarpEngine::RuntimeInstallService and WarpEngine::RuntimeUploadService;
  # soft-deleted, never destroyed.
  class RuntimeVersion < ApplicationRecord
    self.table_name = "runtime_versions"

    include SoftDeletable

    # The sources a version comes from.
    SOURCES = %w[download upload].freeze

    has_many :runtime_components, dependent: nil
    has_many :releases, -> { kept }, dependent: nil

    validates :name, presence: true, format: { with: WarpEngine::Runtime::FORMAT }
    validates :version, presence: true, uniqueness: { scope: :name }
    validates :source, inclusion: { in: SOURCES }
    validates :path, presence: true

    # Returns the runtime's label and the version, e.g. <tt>EmulatorJS 4.2.3</tt>.
    def label = "#{WarpEngine::Runtime.find(name)&.label || name} #{version}"

    # Returns the WarpEngine::Runtime, or +nil+ when it is no longer defined.
    def runtime = WarpEngine::Runtime.find(name)

    # Returns the installed files as a Hash of path (relative to #path) to
    # SHA-256; an empty Hash when there are none.
    def file_digests = (files || {}).to_h

    # Returns the keys of the installed components of the kind +kind+.
    def component_keys(kind) = runtime_components.select { |component| component.kind == kind.to_s }.map(&:key)

    # Returns +true+ when the component +key+ of the kind +kind+ is installed.
    def component?(kind, key) = component_keys(kind).include?(key.to_s)

    ActiveSupport.run_load_hooks(:warp_engine_runtime_version, self)
  end
end
