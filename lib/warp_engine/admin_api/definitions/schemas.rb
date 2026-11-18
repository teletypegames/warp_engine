module WarpEngine
  module AdminApi
    # The declarations of the Admin API resources. Each module's +define+ takes a
    # Registry::Builder and declares its resources and operations; Registry lists
    # the modules.
    module Definitions
      # The named component schemas of the Admin API answers and the request body
      # schemas. Each method builds a fresh schema; the named ones are listed by #all
      # and land in the OpenAPI components.
      module Schemas
        # A component schema: its +name+ and the +schema+ hash.
        Named = Struct.new(:name, :schema)

        # Short name of AdminApi::Schema.
        S = AdminApi::Schema

        module_function

        # A Named schema +name+ of an object with +properties+, by default all required.
        def named(name, properties, required: properties.keys)
          Named.new(name, S.object(properties, required: required))
        end

        # The nullable +createdAt+ and +updatedAt+ properties.
        def timestamps
          { createdAt: S.nullable(S.datetime), updatedAt: S.nullable(S.datetime) }
        end

        # A nullable string schema.
        def text = S.nullable(S.string)

        # The +Software+ schema, with the optional included lists of <tt>GET /softwares/:id</tt>.
        def software
          base = {
            id: S.id, name: S.string, title: S.string, author: text, desc: text, story: text,
            license: text, platform: S.enum(WarpEngine::Platform.names), status: text, category: text,
            highlighted: S.nullable(S.boolean), shelfName: text, ownerType: text, ownerId: S.nullable(S.integer), **timestamps
          }
          included = {
            releases:      S.array(S.ref("Release"), "With include=releases"),
            images:        S.array(S.ref("SoftwareImage"), "With include=images"),
            externalLinks: S.array(S.ref("ExternalLink"), "With include=externalLinks"),
            extras:        S.object({}, description: "With include=extras: one key per additional resource", additional: true)
          }
          named("Software", base.merge(included), required: base.keys)
        end

        # The body of creating or changing a software.
        def software_body
          S.object({
            name: S.string("Internal name, unique"), title: S.string, author: text, desc: text, story: text,
            license: text, platform: S.enum(WarpEngine::Platform.names),
            status: S.nullable(S.string("A key from software_statuses")),
            category: S.nullable(S.string("A key from software_categories; a new word is registered for review")),
            highlighted: S.boolean,
            shelfName: S.nullable(S.string("File name on a shelf (A-Z, 0-9, -); null uses the name"))
          })
        end

        # The +Release+ schema, with its assets.
        def release
          named("Release", { id: S.id, softwareId: S.integer, version: S.string, channel: S.enum(WarpEngine::Channels::ALL), commitSha: text,
                             assets: S.array(S.ref("ReleaseAsset")), **timestamps })
        end

        # The body of a scaffold (<tt>POST /softwares/scaffold</tt>).
        def scaffold_body
          S.object({ name: S.string("Software and repository name: a-z, 0-9 and dashes"), title: S.string,
                     platform: S.enum(WarpEngine::Platform.names), category: text, description: text })
        end

        # The +Scaffold+ schema, what a scaffold made.
        def scaffold
          named("Scaffold", { software: S.ref("Software"),
                              repository: S.object({ owner: S.string, name: S.string, htmlUrl: text, cloneUrl: text, sshUrl: text }),
                              pipelineId: S.nullable(S.integer), warnings: S.array(S.string) })
        end

        # The body of creating or changing a release.
        def release_body = S.object({ version: S.string })

        # The +ReleaseAsset+ schema.
        def release_asset
          named("ReleaseAsset", { id: S.id, releaseId: S.integer, kind: S.enum(WarpEngine::ReleaseAsset::KINDS),
                                  path: S.string, **timestamps })
        end

        # The body of creating or changing a release asset.
        def release_asset_body
          S.object({ kind: S.enum(WarpEngine::ReleaseAsset::KINDS), path: S.string("Absolute path in the artifact store") })
        end

        # The +ExternalLink+ schema.
        def external_link
          named("ExternalLink", { id: S.id, softwareId: S.integer, label: S.string, url: S.string, **timestamps })
        end

        # The body of creating or changing an external link.
        def external_link_body = S.object({ label: S.string, url: S.string })

        # The +SoftwareImage+ schema.
        def software_image
          named("SoftwareImage", { id: S.id, softwareId: S.integer, imageId: S.integer, isDefault: S.boolean,
                                   position: S.integer, url: S.nullable(S.string), **timestamps })
        end

        # The body of linking a library image to a software.
        def software_image_body
          S.object({ imageId: S.integer("An image of the host's image library"), isDefault: S.boolean,
                     position: S.integer(minimum: 0) })
        end

        # The multipart body of uploading an image for a software.
        def software_image_upload_body
          S.object({ file: S.string("The image file", format: "binary"), isDefault: S.boolean,
                     position: S.integer(minimum: 0) })
        end

        # The +PlatformLink+ schema.
        def platform_link
          named("PlatformLink", { id: S.id, platform: S.string, name: S.string, url: S.string,
                                  position: S.integer, **timestamps })
        end

        # The body of creating or changing a platform link.
        def platform_link_body
          S.object({ platform: S.enum(WarpEngine::Platform.names), name: S.string, url: S.string,
                     position: S.integer(minimum: 0) })
        end

        # The +SoftwareStatus+ schema.
        def software_status
          named("SoftwareStatus", { id: S.id, key: S.string, label: S.string, position: S.integer,
                                    defaultVisible: S.boolean, badge: text, softwareCount: S.integer, **timestamps })
        end

        # The body of creating or changing a software status.
        def software_status_body
          S.object({ key: S.string(pattern: "^[a-z0-9_-]+$"), label: S.string, position: S.integer,
                     defaultVisible: S.boolean, badge: text })
        end

        # The +SoftwareCategory+ schema.
        def software_category
          named("SoftwareCategory", { id: S.id, key: S.string, label: S.string, position: S.integer,
                                      needsReview: S.boolean, softwareCount: S.integer, **timestamps })
        end

        # The body of creating or changing a software category.
        def software_category_body
          S.object({ key: S.string, label: S.string, position: S.integer, needsReview: S.boolean })
        end

        # The +Download+ schema, one entry of the download log.
        def download
          named("Download", { id: S.id, filePath: S.string, releaseId: S.nullable(S.integer),
                              softwareId: S.nullable(S.integer), ipAddress: text, userAgent: text, referer: text,
                              **timestamps })
        end

        # The +DownloadSummary+ schema: downloads in total, today, this week and this month.
        def download_summary
          named("DownloadSummary", { total: S.integer, today: S.integer, week: S.integer, month: S.integer })
        end

        # The +FileDownloads+ schema: downloads of one file.
        def file_downloads
          named("FileDownloads", { filePath: S.string, downloads: S.integer, lastDownloadAt: S.nullable(S.datetime) })
        end

        # The +SoftwareDownloads+ schema: downloads of one software.
        def software_downloads
          named("SoftwareDownloads", { softwareId: S.integer, name: S.string, title: S.string, downloads: S.integer })
        end

        # The +SoftwareDownloadStats+ schema: downloads of one software by release and file.
        def software_download_stats
          named("SoftwareDownloadStats", {
            total:    S.integer,
            releases: S.array(S.object({ releaseId: S.integer, version: S.string, downloads: S.integer,
                                         files: S.array(S.ref("FileDownloads")) },
                                       required: %i[releaseId version downloads files]))
          })
        end

        # The +Pipeline+ schema, one CI repository.
        def pipeline
          named("Pipeline", { id: S.id, repoId: S.integer, repoOwner: S.string, repoName: S.string,
                              fullName: S.string, platform: S.string, active: S.boolean,
                              softwareId: S.nullable(S.integer), lastPipelineStatus: text,
                              lastPipelineAt: S.nullable(S.datetime), **timestamps })
        end

        # The body of changing a pipeline's platform or software.
        def pipeline_body
          S.object({ platform: S.enum(WarpEngine::Platform.names + [ WarpEngine::Pipeline::UNKNOWN_PLATFORM ]),
                     softwareId: S.nullable(S.integer("One pipeline per software: taking one moves it here")) })
        end

        # The +PipelineRun+ schema, one run on the CI server.
        def pipeline_run
          named("PipelineRun", { number: S.integer, status: text, branch: text, message: text,
                                 createdAt: S.nullable(S.datetime), url: text, commit: text, event: text,
                                 ref: text })
        end

        # The +PipelineSync+ schema: the pipelines a sync created, updated and deactivated.
        def pipeline_sync
          named("PipelineSync", { created: S.array(S.ref("Pipeline")), updated: S.array(S.ref("Pipeline")),
                                  deactivated: S.array(S.ref("Pipeline")) })
        end

        # The +RuntimeVersion+ schema, one installed version of a runtime.
        def runtime_version
          named("RuntimeVersion", { id: S.id, name: S.string, version: S.string, source: S.enum(WarpEngine::RuntimeVersion::SOURCES),
                                    path: S.string("Relative to the artifact store"), sizeBytes: S.integer,
                                    components: S.array(S.object({ kind: S.string, key: S.string })),
                                    releases: S.integer("Releases bound to it"), **timestamps })
        end

        # The body of installing a runtime.
        def runtime_install_body
          S.object({ name: S.string("A downloaded runtime"), version: S.nullable(S.string("Default: the chosen one")),
                     dryRun: S.boolean("Only report what would be fetched") }, required: [ :name ])
        end

        # The +RuntimeInstall+ schema: what an install did.
        def runtime_install
          named("RuntimeInstall", { name: S.string, version: S.string, fetched: S.array(S.string), kept: S.array(S.string),
                                    components: S.object({}, additional: true), dryRun: S.boolean })
        end

        # The +FileEntry+ schema, one file or directory of the artifact store.
        def file_entry
          named("FileEntry", { name: S.string, path: S.string, type: S.enum(%w[file directory]),
                               size: S.nullable(S.integer), modifiedAt: S.nullable(S.datetime),
                               downloads: S.nullable(S.integer) })
        end

        # The +FilePath+ schema: a path in the artifact store.
        def file_path
          named("FilePath", { path: S.string("Relative to the artifact store") })
        end

        # The +ApplicationToken+ schema; the plain token and CI sync only when issued.
        def application_token
          named("ApplicationToken", {
            id: S.id, name: S.string, tokenPrefix: S.string, ownerType: S.string, ownerId: S.integer,
            scopes: S.array(S.string), unrestricted: S.boolean, expiresAt: S.nullable(S.datetime),
            lastUsedAt: S.nullable(S.datetime), **timestamps,
            plainToken: S.string("Only in the answer that created it; never shown again"),
            sync: S.nullable(S.object({ synced: S.integer, failed: S.integer }, required: %i[synced failed]))
          }, required: %i[id name tokenPrefix ownerType ownerId scopes unrestricted expiresAt lastUsedAt createdAt updatedAt])
        end

        # The +SyncServer+ schema, an engine the releases are pushed to.
        def sync_server
          named("SyncServer", { id: S.id, label: S.string, host: S.string, active: S.boolean,
                                secretPrefix: S.nullable(S.string("The first characters of the token")),
                                lastSyncedAt: S.nullable(S.datetime), lastError: text, **timestamps })
        end

        # The body of adding or changing a sync server.
        def sync_server_body
          S.object({ label: S.string, host: S.string("Base URL of the other engine, its mount included"),
                     secret: S.string("A token with the sync scope it issued; write-only, empty keeps the stored one"),
                     active: S.boolean })
        end

        # The +SyncCheck+ schema: whether the other engine accepts the token.
        def sync_check
          named("SyncCheck", { ok: S.boolean, status: S.nullable(S.integer), version: text, message: S.string })
        end

        # The +SyncPush+ schema: the releases a run sends, to which servers, how
        # many pushes were queued (none on a dry run) and which releases were skipped.
        def sync_push
          named("SyncPush", { dryRun: S.boolean, queued: S.integer, servers: S.array(S.integer),
                              releases: S.array(S.object({ software: S.string, version: S.string }, required: %i[software version])),
                              skipped: S.array(S.string) })
        end

        # The body of a sync run (WarpEngine::Sync::Criteria).
        def sync_run_body
          list = ->(description) { S.array(S.string, description) }
          S.object({
            all: S.boolean("Every allowed release, oldest first (a full sync); default: the newest of each software"),
            filtered: S.boolean("Apply the configured filters (default true); without them every software and kind goes"),
            channels: S.array(S.enum(WarpEngine::Channels::ALL), "Default: the configured allowed_channels"),
            softwares: list.call("Software names, * as a wildcard"), software: S.string("One software, by name"),
            platforms: list.call("Platform names"), categories: list.call("Category keys"), statuses: list.call("Status keys"),
            skipExisting: S.boolean("Leave out what the server already has, asked when each push runs (default true)"),
            dryRun: S.boolean("Only answer what would go")
          })
        end

        # The +SyncEvent+ schema, one line of the sync log.
        def sync_event
          named("SyncEvent", {
            id: S.id, syncServerId: S.nullable(S.integer), direction: S.enum(WarpEngine::SyncEvent::DIRECTIONS),
            status: S.enum(WarpEngine::SyncEvent::STATUSES), softwareName: text, platform: text, version: text,
            releaseId: S.nullable(S.integer), step: text, httpStatus: S.nullable(S.integer), message: text,
            filesCount: S.nullable(S.integer), bytes: S.nullable(S.integer), durationMs: S.nullable(S.integer),
            attempt: S.nullable(S.integer), tokenPrefix: text, **timestamps
          })
        end

        # The body of issuing or changing an application token.
        def application_token_body
          S.object({
            name: S.string, ownerId: S.integer("Defaults to the caller's owner"),
            scopes: S.array(S.string, "Admin scopes no wider than the caller's own"),
            unrestricted: S.boolean("Only an unrestricted caller may ask"),
            expiresAt: S.nullable(S.datetime("Not later than the caller's own expiry"))
          })
        end

        # The +DeviceGrant+ schema, one device sign-in.
        def device_grant
          named("DeviceGrant", {
            id: S.id, userCode: S.string, clientName: text, state: S.enum(%w[pending approved denied expired]),
            subjectType: text, subjectId: S.nullable(S.integer), applicationTokenId: S.nullable(S.integer),
            approvedAt: S.nullable(S.datetime), deniedAt: S.nullable(S.datetime), expiresAt: S.datetime, **timestamps
          })
        end

        # The +Principal+ schema answered by <tt>GET /me</tt>.
        def principal
          named("Principal", {
            label: text, ownerType: text, ownerId: S.nullable(S.integer), scopes: S.array(S.string),
            unrestricted: S.boolean, tokenPrefix: text, expiresAt: S.nullable(S.datetime),
            resources: S.array(S.string, "The resources this caller may use here"),
            readOnly: S.boolean, mcp: S.boolean
          })
        end

        # The +Extra+ schema: what a host-defined additional resource holds for a software.
        def extra
          named("Extra", { association: S.string, multiple: S.boolean,
                           value: { description: "An object, or an array of objects when multiple" } })
        end

        # Every Named component schema.
        def all
          [ software, release, release_asset, external_link, software_image, platform_link, software_status,
            software_category, download, download_summary, file_downloads, software_downloads,
            software_download_stats, pipeline, pipeline_run, pipeline_sync, file_entry, file_path,
            application_token, device_grant, principal, extra, scaffold, sync_server, sync_check, sync_push,
            sync_event ]
        end
      end
    end
  end
end
