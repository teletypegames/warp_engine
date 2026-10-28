module WarpEngine
  module AdminApi
    module Definitions
      # The +files+ resource: browsing and changing the artifact store through WarpEngine::FileManagerService.
      module Files
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        module_function

        # Declares the +files+ resource on +api+: list a directory, upload a file
        # (multipart), create a directory, rename and delete.
        def define(api)
          api.resource(:files, label: "Files") do |r|
            r.action :get, "/files", name: :list, summary: "One directory of the artifact store",
                     item: X.file_entry, many: true,
                     query: { dir: S.string("Relative to the artifact store; empty is its root") } do |ctx|
              entries = service.list(ctx[:dir].to_s, with_download_counts: true)
              ctx.ok(entries.map { |entry| entry_payload(entry) })
            end

            r.action :post, "/files", name: :upload, summary: "Upload a file into a directory", item: X.file_path,
                     status: 201, multipart: true, required: %i[file],
                     body: S.object({ dir: S.string, file: S.string("The file", format: "binary") }) do |ctx|
              upload = ctx[:file]
              raise Error.bad_request("file must be an uploaded file") unless upload.respond_to?(:original_filename)

              ctx.created({ path: service.upload(ctx[:dir].to_s, upload) })
            end

            r.action :post, "/files/directories", name: :mkdir, summary: "Create a directory", item: X.file_path,
                     status: 201, required: %i[name], body: S.object({ dir: S.string, name: S.string }) do |ctx|
              ctx.created({ path: service.mkdir(ctx[:dir].to_s, ctx[:name].to_s) })
            end

            r.action :patch, "/files", name: :rename, summary: "Rename a file or directory in place", item: X.file_path,
                     required: %i[path newName], body: S.object({ path: S.string, newName: S.string }) do |ctx|
              ctx.ok({ path: service.rename(ctx[:path].to_s, ctx[:newName].to_s) })
            end

            r.delete "/files", summary: "Delete a file or an empty directory", required: %i[path],
                     query: { path: S.string("Relative to the artifact store") } do |ctx|
              service.delete(ctx[:path].to_s)
              ctx.no_content
            end
          end
        end

        # A new WarpEngine::FileManagerService.
        def service = WarpEngine::FileManagerService.new

        # The +FileEntry+ answer of one directory listing +entry+.
        def entry_payload(entry)
          {
            name:       entry[:name],
            path:       entry[:path],
            type:       entry[:type].to_s,
            size:       entry[:size],
            modifiedAt: entry[:mtime],
            downloads:  entry[:downloads]
          }
        end
      end
    end
  end
end
