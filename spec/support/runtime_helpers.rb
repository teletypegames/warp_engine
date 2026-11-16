require "digest"
require "zip"

module RuntimeHelpers
  def stub_runtime(name, files:, template: "emulatorjs.html", components: {}, params: {}, version: "1.0")
    dir = Dir.mktmpdir
    checksums = File.join(dir, "#{name}-#{version}.sha256")
    File.write(checksums, files.map { |file, body| "#{Digest::SHA256.hexdigest(body)}  #{file}\n" }.join)
    builder = WarpEngine::Runtime::Builder.new(name)
    builder.label(name.to_s.titleize)
    builder.version(version, source: "https://cdn.example/#{name}/#{version}/", checksums: checksums)
    components.each { |kind, patterns| builder.component(kind, *patterns) }
    params.each { |param, options| builder.param(param, **options) }
    builder.template(template)
    definition = builder.build
    allow(WarpEngine.config).to receive(:runtimes).and_return(WarpEngine.config.runtimes.merge(name.to_s => definition))
    definition
  end

  def fake_fetcher(files, prefix:)
    ->(url) { files.fetch(url.delete_prefix(prefix)) { raise "unexpected fetch #{url}" } }
  end

  def runtime_zip(entries)
    path = File.join(Dir.mktmpdir, "runtime.zip")
    Zip::File.open(path, create: true) do |zip|
      entries.each { |name, body| zip.get_output_stream(name) { |io| io.write(body) } }
    end
    path
  end

  def install_runtime_version(name:, version:, files:, components: {}, source: "download")
    directory = WarpEngine::Runtime.directory(name, version)
    root = File.join(WarpEngine.config.file_container_path, directory)
    files.each do |file, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, file)))
      File.binwrite(File.join(root, file), body)
    end
    record = WarpEngine::RuntimeVersion.create!(name: name, version: version, source: source, path: directory,
                                                files: files.transform_values { |body| Digest::SHA256.hexdigest(body) },
                                                size_bytes: files.values.sum(&:bytesize))
    components.each { |kind, keys| Array(keys).each { |key| record.runtime_components.create!(kind: kind, key: key) } }
    record
  end
end

RSpec.configure { |config| config.include RuntimeHelpers }
