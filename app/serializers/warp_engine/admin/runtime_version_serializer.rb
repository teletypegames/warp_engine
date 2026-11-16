module WarpEngine
  module Admin
    # Admin API view of a WarpEngine::RuntimeVersion: id, runtime name and
    # version, source, path, size, the installed components (+kind+ and
    # +key+), the number of releases bound to it, and timestamps.
    class RuntimeVersionSerializer < Blueprinter::Base
      identifier :id
      fields :name, :version, :source, :path
      field :size_bytes, name: :sizeBytes
      field(:components) { |version| version.runtime_components.map { |component| { kind: component.kind, key: component.key } } }
      field(:releases) { |version| version.releases.count }
      include Timestamps
    end
  end
end
