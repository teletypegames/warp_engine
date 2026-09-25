module WarpEngine
  module AdminApi
    module Definitions
      module Schemas
        Named = Struct.new(:name, :schema)

        S = AdminApi::Schema

        module_function

        def named(name, properties, required: properties.keys)
          Named.new(name, S.object(properties, required: required))
        end

        def timestamps
          { createdAt: S.nullable(S.datetime), updatedAt: S.nullable(S.datetime) }
        end

        def text = S.nullable(S.string)

        def software
          base = {
            id: S.id, name: S.string, title: S.string, author: text, desc: text, story: text,
            license: text, platform: S.enum(WarpEngine::Platform::NAMES), status: text, category: text,
            highlighted: S.nullable(S.boolean), ownerType: text, ownerId: S.nullable(S.integer), **timestamps
          }
          included = {
            releases:      S.array(S.ref("Release"), "With include=releases"),
            images:        S.array(S.ref("SoftwareImage"), "With include=images"),
            externalLinks: S.array(S.ref("ExternalLink"), "With include=externalLinks"),
            extras:        S.object({}, description: "With include=extras: one key per additional resource", additional: true)
          }
          named("Software", base.merge(included), required: base.keys)
        end

        def software_body
          S.object({
            name: S.string("Internal name, unique"), title: S.string, author: text, desc: text, story: text,
            license: text, platform: S.enum(WarpEngine::Platform::NAMES),
            status: S.nullable(S.string("A key from software_statuses")),
            category: S.nullable(S.string("A key from software_categories; a new word is registered for review")),
            highlighted: S.boolean
          })
        end

        def release
          named("Release", { id: S.id, softwareId: S.integer, version: S.string,
                             assets: S.array(S.ref("ReleaseAsset")), **timestamps })
        end

        def release_body = S.object({ version: S.string })

        def release_asset
          named("ReleaseAsset", { id: S.id, releaseId: S.integer, kind: S.enum(WarpEngine::ReleaseAsset::KINDS),
                                  path: S.string, **timestamps })
        end

        def release_asset_body
          S.object({ kind: S.enum(WarpEngine::ReleaseAsset::KINDS), path: S.string("Absolute path in the artifact store") })
        end

        def external_link
          named("ExternalLink", { id: S.id, softwareId: S.integer, label: S.string, url: S.string, **timestamps })
        end

        def external_link_body = S.object({ label: S.string, url: S.string })

        def software_image
          named("SoftwareImage", { id: S.id, softwareId: S.integer, imageId: S.integer, isDefault: S.boolean,
                                   position: S.integer, url: S.nullable(S.string), **timestamps })
        end

        def software_image_body
          S.object({ imageId: S.integer("An image of the host's image library"), isDefault: S.boolean,
                     position: S.integer(minimum: 0) })
        end

        def software_image_upload_body
          S.object({ file: S.string("The image file", format: "binary"), isDefault: S.boolean,
                     position: S.integer(minimum: 0) })
        end

        def platform_link
          named("PlatformLink", { id: S.id, platform: S.string, name: S.string, url: S.string,
                                  position: S.integer, **timestamps })
        end

        def platform_link_body
          S.object({ platform: S.enum(WarpEngine::Platform::NAMES), name: S.string, url: S.string,
                     position: S.integer(minimum: 0) })
        end

        def software_status
          named("SoftwareStatus", { id: S.id, key: S.string, label: S.string, position: S.integer,
                                    defaultVisible: S.boolean, badge: text, softwareCount: S.integer, **timestamps })
        end

        def software_status_body
          S.object({ key: S.string(pattern: "^[a-z0-9_-]+$"), label: S.string, position: S.integer,
                     defaultVisible: S.boolean, badge: text })
        end

        def software_category
          named("SoftwareCategory", { id: S.id, key: S.string, label: S.string, position: S.integer,
                                      needsReview: S.boolean, softwareCount: S.integer, **timestamps })
        end

        def software_category_body
          S.object({ key: S.string, label: S.string, position: S.integer, needsReview: S.boolean })
        end

        def download
          named("Download", { id: S.id, filePath: S.string, releaseId: S.nullable(S.integer),
                              softwareId: S.nullable(S.integer), ipAddress: text, userAgent: text, referer: text,
                              **timestamps })
        end

        def download_summary
          named("DownloadSummary", { total: S.integer, today: S.integer, week: S.integer, month: S.integer })
        end

        def file_downloads
          named("FileDownloads", { filePath: S.string, downloads: S.integer, lastDownloadAt: S.nullable(S.datetime) })
        end

        def software_downloads
          named("SoftwareDownloads", { softwareId: S.integer, name: S.string, title: S.string, downloads: S.integer })
        end

        def software_download_stats
          named("SoftwareDownloadStats", {
            total:    S.integer,
            releases: S.array(S.object({ releaseId: S.integer, version: S.string, downloads: S.integer,
                                         files: S.array(S.ref("FileDownloads")) },
                                       required: %i[releaseId version downloads files]))
          })
        end

        def pipeline
          named("Pipeline", { id: S.id, repoId: S.integer, repoOwner: S.string, repoName: S.string,
                              fullName: S.string, platform: S.string, active: S.boolean,
                              softwareId: S.nullable(S.integer), lastPipelineStatus: text,
                              lastPipelineAt: S.nullable(S.datetime), **timestamps })
        end

        def pipeline_body
          S.object({ platform: S.enum(WarpEngine::Platform::NAMES + [ WarpEngine::Pipeline::UNKNOWN_PLATFORM ]),
                     softwareId: S.nullable(S.integer("One pipeline per software: taking one moves it here")) })
        end

        def pipeline_run
          named("PipelineRun", { number: S.integer, status: text, branch: text, message: text,
                                 createdAt: S.nullable(S.datetime), url: text })
        end

        def pipeline_sync
          named("PipelineSync", { created: S.array(S.ref("Pipeline")), updated: S.array(S.ref("Pipeline")),
                                  deactivated: S.array(S.ref("Pipeline")) })
        end

        def file_entry
          named("FileEntry", { name: S.string, path: S.string, type: S.enum(%w[file directory]),
                               size: S.nullable(S.integer), modifiedAt: S.nullable(S.datetime),
                               downloads: S.nullable(S.integer) })
        end

        def file_path
          named("FilePath", { path: S.string("Relative to the artifact store") })
        end

        def application_token
          named("ApplicationToken", {
            id: S.id, name: S.string, tokenPrefix: S.string, ownerType: S.string, ownerId: S.integer,
            scopes: S.array(S.string), unrestricted: S.boolean, expiresAt: S.nullable(S.datetime),
            lastUsedAt: S.nullable(S.datetime), **timestamps,
            plainToken: S.string("Only in the answer that created it; never shown again"),
            sync: S.nullable(S.object({ synced: S.integer, failed: S.integer }, required: %i[synced failed]))
          }, required: %i[id name tokenPrefix ownerType ownerId scopes unrestricted expiresAt lastUsedAt createdAt updatedAt])
        end

        def application_token_body
          S.object({
            name: S.string, ownerId: S.integer("Defaults to the caller's owner"),
            scopes: S.array(S.string, "Admin scopes no wider than the caller's own"),
            unrestricted: S.boolean("Only an unrestricted caller may ask"),
            expiresAt: S.nullable(S.datetime("Not later than the caller's own expiry"))
          })
        end

        def device_grant
          named("DeviceGrant", {
            id: S.id, userCode: S.string, clientName: text, state: S.enum(%w[pending approved denied expired]),
            subjectType: text, subjectId: S.nullable(S.integer), applicationTokenId: S.nullable(S.integer),
            approvedAt: S.nullable(S.datetime), deniedAt: S.nullable(S.datetime), expiresAt: S.datetime, **timestamps
          })
        end

        def principal
          named("Principal", {
            label: text, ownerType: text, ownerId: S.nullable(S.integer), scopes: S.array(S.string),
            unrestricted: S.boolean, tokenPrefix: text, expiresAt: S.nullable(S.datetime),
            resources: S.array(S.string, "The resources this caller may use here"),
            readOnly: S.boolean, mcp: S.boolean
          })
        end

        def extra
          named("Extra", { association: S.string, multiple: S.boolean,
                           value: { description: "An object, or an array of objects when multiple" } })
        end

        def all
          [ software, release, release_asset, external_link, software_image, platform_link, software_status,
            software_category, download, download_summary, file_downloads, software_downloads,
            software_download_stats, pipeline, pipeline_run, pipeline_sync, file_entry, file_path,
            application_token, device_grant, principal, extra ]
        end
      end
    end
  end
end
