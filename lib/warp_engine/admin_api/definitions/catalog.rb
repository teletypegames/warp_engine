module WarpEngine
  module AdminApi
    module Definitions
      # The catalog resources: softwares, releases, release assets, external links,
      # fork links, software images and the host-defined additional resources (extras).
      module Catalog
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        # What <tt>GET /softwares/:id</tt> can include, comma-separated in +include+.
        INCLUDES = %w[releases images externalLinks extras].freeze

        module_function

        # Declares every catalog resource on +api+.
        def define(api)
          softwares(api)
          releases(api)
          release_assets(api)
          external_links(api)
          fork_links(api)
          software_images(api)
          extras(api)
        end

        # Declares the +softwares+ resource on +api+: filtered list, get with includes, create, update, delete.
        def softwares(api)
          api.resource(:softwares, label: "Softwares") do |r|
            r.list "/softwares", summary: "List the softwares", item: X.software,
                   filters: {
                     name:        S.string("Name contains"),
                     title:       S.string("Title contains"),
                     author:      S.string("Author contains"),
                     platform:    S.enum(WarpEngine::Platform.names),
                     status:      S.string("A status key"),
                     category:    S.string("A category key"),
                     highlighted: S.boolean,
                     q:           S.string("Matched against title and name")
                   },
                   sort: { title: :title, name: :name, createdAt: :created_at, updatedAt: :updated_at } do |ctx|
              scope = WarpEngine::Software.kept.with_platform(ctx[:platform]).with_statuses(ctx[:status].presence)
                                          .with_category(ctx[:category]).search(ctx[:q])
              %i[name title author].each do |column|
                scope = scope.where("softwares.#{column} LIKE ?", like(ctx[column])) if ctx[column].present?
              end
              scope = scope.where(highlighted: ctx[:highlighted]) if ctx.key?(:highlighted)
              ctx.list(scope, Admin::SoftwareSerializer)
            end

            r.get "/softwares/:id", summary: "One software, optionally with what belongs to it", item: X.software,
                  query: { include: S.string("Comma-separated: #{INCLUDES.join(', ')}") } do |ctx|
              ctx.ok(software_payload(WarpEngine::Software.kept.find(ctx.id), ctx[:include]))
            end

            r.create "/softwares", summary: "Create a software (a deleted one of the name comes back)", body: X.software_body,
                     required: %i[name title platform], item: X.software do |ctx|
              software = ctx.save!(revived(WarpEngine::Software, ctx.attributes, :name))
              ctx.created(Admin::SoftwareSerializer.render_as_hash(software))
            end

            r.action :post, "/softwares/scaffold", name: :scaffold, status: 201,
                     summary: "Start a software: forge repository, CI, CI token and a draft catalog entry",
                     body: X.scaffold_body, required: %i[name title platform], item: X.scaffold do |ctx|
              result = WarpEngine::ScaffoldService.new.scaffold(
                name: ctx[:name].to_s, title: ctx[:title].to_s, platform: ctx[:platform].to_s, app: ctx[:app].presence,
                owner: ctx.principal.owner,
                category: ctx[:category], description: ctx[:description], license: ctx[:license],
                fork_of: ctx[:forkOf].presence
              )
              ctx.created(scaffold_payload(result))
            rescue WarpEngine::ScaffoldService::Error => e
              raise Error.conflict(e.message)
            rescue WarpEngine::Forge::Error => e
              raise Error.new(502, e.message)
            end

            r.update "/softwares/:id", summary: "Change a software", body: X.software_body, item: X.software do |ctx|
              software = WarpEngine::Software.kept.find(ctx.id)
              software.assign_attributes(ctx.attributes)
              ctx.ok(Admin::SoftwareSerializer.render_as_hash(ctx.save!(software)))
            end

            r.delete "/softwares/:id", summary: "Delete a software (soft): it and its releases leave every listing" do |ctx|
              WarpEngine::Software.kept.find(ctx.id).soft_delete!
              ctx.no_content
            end
          end
        end

        # Declares the +releases+ resource on +api+: a software's releases, add, get, update, delete.
        def releases(api)
          api.resource(:releases, label: "Releases") do |r|
            r.list "/softwares/:softwareId/releases", summary: "The releases of a software", item: X.release,
                   filters: { commitSha: S.string("The commit the CI built the release from"), channel: S.enum(WarpEngine::Channels::ALL) },
                   sort: { createdAt: :created_at, version: :version }, default_sort: "-createdAt" do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              scope = software.releases.includes(:release_assets)
              scope = scope.where(commit_sha: ctx[:commitSha]) if ctx[:commitSha].present?
              scope = scope.where(channel: ctx[:channel]) if ctx[:channel].present?
              ctx.list(scope, Admin::ReleaseSerializer)
            end

            r.create "/softwares/:softwareId/releases", summary: "Add a release (a deleted one of the version comes back)",
                     body: X.release_body, required: %i[version], item: X.release do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              release = ctx.save!(revived(WarpEngine::Release, ctx.attributes.merge("software_id" => software.id), :software_id, :version))
              ctx.created(Admin::ReleaseSerializer.render_as_hash(release))
            end

            r.get "/releases/:id", summary: "One release with its assets", item: X.release do |ctx|
              ctx.ok(Admin::ReleaseSerializer.render_as_hash(release(ctx.id)))
            end

            r.update "/releases/:id", summary: "Change a release", body: X.release_body, item: X.release do |ctx|
              release = release(ctx.id)
              release.assign_attributes(ctx.attributes)
              ctx.ok(Admin::ReleaseSerializer.render_as_hash(ctx.save!(release)))
            end

            r.delete "/releases/:id", summary: "Delete a release (soft) with its assets" do |ctx|
              release(ctx.id).soft_delete!
              ctx.no_content
            end
          end
        end

        # Declares the +release_assets+ resource on +api+: a release's assets, add, get,
        # update, delete. An +html+ asset is refused (422) on platforms that are not web playable.
        def release_assets(api)
          api.resource(:release_assets, label: "Release assets") do |r|
            r.action :get, "/releases/:releaseId/assets", name: :list, summary: "The assets of a release",
                     item: X.release_asset, many: true do |ctx|
              assets = release(ctx[:releaseId]).release_assets.sort_by(&:kind)
              ctx.ok(Admin::ReleaseAssetSerializer.render_as_hash(assets))
            end

            r.create "/releases/:releaseId/assets", summary: "Add an asset to a release", body: X.release_asset_body,
                     required: %i[kind path], item: X.release_asset do |ctx|
              release = release(ctx[:releaseId])
              check_web_playable!(release, ctx[:kind])
              asset = ctx.save!(revived(WarpEngine::ReleaseAsset, ctx.attributes.merge("release_id" => release.id), :release_id, :kind))
              ctx.created(Admin::ReleaseAssetSerializer.render_as_hash(asset))
            end

            r.get "/assets/:id", summary: "One asset", item: X.release_asset do |ctx|
              ctx.ok(Admin::ReleaseAssetSerializer.render_as_hash(asset(ctx.id)))
            end

            r.update "/assets/:id", summary: "Change an asset", body: X.release_asset_body, item: X.release_asset do |ctx|
              asset = asset(ctx.id)
              check_web_playable!(asset.release, ctx[:kind]) if ctx.key?(:kind)
              asset.assign_attributes(ctx.attributes)
              ctx.ok(Admin::ReleaseAssetSerializer.render_as_hash(ctx.save!(asset)))
            end

            r.delete "/assets/:id", summary: "Delete an asset (soft)" do |ctx|
              asset(ctx.id).soft_delete!
              ctx.no_content
            end
          end
        end

        # Declares the +fork_links+ resource on +api+: the forks other engines
        # announced, list (filtered by status or software), get, and moderate
        # (change the status).
        def fork_links(api)
          api.resource(:fork_links, label: "Fork links") do |r|
            r.list "/fork_links", summary: "The forks other engines announced", item: X.fork_link,
                   filters: { status: S.enum(WarpEngine::ForkLink::STATUSES), softwareId: S.integer },
                   sort: { createdAt: :created_at, checkedAt: :checked_at }, default_sort: "-createdAt" do |ctx|
              scope = WarpEngine::ForkLink.kept.includes(:software)
              scope = scope.where(status: ctx[:status]) if ctx[:status].present?
              scope = scope.where(software_id: ctx[:softwareId]) if ctx[:softwareId].present?
              ctx.list(scope, Admin::ForkLinkSerializer)
            end

            r.get "/fork_links/:id", summary: "One announced fork", item: X.fork_link do |ctx|
              ctx.ok(Admin::ForkLinkSerializer.render_as_hash(WarpEngine::ForkLink.kept.find(ctx.id)))
            end

            r.update "/fork_links/:id", summary: "Moderate an announced fork: visible lists it, hidden keeps it out",
                     body: X.fork_link_body, required: %i[status], item: X.fork_link do |ctx|
              link = WarpEngine::ForkLink.kept.find(ctx.id)
              link.assign_attributes(ctx.attributes)
              ctx.ok(Admin::ForkLinkSerializer.render_as_hash(ctx.save!(link)))
            end

            r.delete "/fork_links/:id", summary: "Delete an announced fork (soft); a new announcement brings it back as pending" do |ctx|
              WarpEngine::ForkLink.kept.find(ctx.id).soft_delete!
              ctx.no_content
            end
          end
        end

        # Declares the +external_links+ resource on +api+: a software's links, add, get, update, delete.
        def external_links(api)
          api.resource(:external_links, label: "External links") do |r|
            r.action :get, "/softwares/:softwareId/external_links", name: :list,
                     summary: "The external links of a software", item: X.external_link, many: true do |ctx|
              links = WarpEngine::Software.kept.find(ctx[:softwareId]).external_links.order(:id)
              ctx.ok(Admin::ExternalLinkSerializer.render_as_hash(links))
            end

            r.create "/softwares/:softwareId/external_links", summary: "Add an external link",
                     body: X.external_link_body, required: %i[label url], item: X.external_link do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              link = ctx.save!(WarpEngine::ExternalLink.new(ctx.attributes.merge("software" => software)))
              ctx.created(Admin::ExternalLinkSerializer.render_as_hash(link))
            end

            r.get "/external_links/:id", summary: "One external link", item: X.external_link do |ctx|
              ctx.ok(Admin::ExternalLinkSerializer.render_as_hash(WarpEngine::ExternalLink.kept.find(ctx.id)))
            end

            r.update "/external_links/:id", summary: "Change an external link", body: X.external_link_body,
                     item: X.external_link do |ctx|
              link = WarpEngine::ExternalLink.kept.find(ctx.id)
              link.assign_attributes(ctx.attributes)
              ctx.ok(Admin::ExternalLinkSerializer.render_as_hash(ctx.save!(link)))
            end

            r.delete "/external_links/:id", summary: "Delete an external link (soft)" do |ctx|
              WarpEngine::ExternalLink.kept.find(ctx.id).soft_delete!
              ctx.no_content
            end
          end
        end

        # Declares the +software_images+ resource on +api+: a software's images, link a
        # library image, upload a new image (multipart), get, update, unlink.
        def software_images(api)
          api.resource(:software_images, label: "Software images") do |r|
            r.action :get, "/softwares/:softwareId/images", name: :list, summary: "The images of a software, in order",
                     item: X.software_image, many: true do |ctx|
              images = WarpEngine::Software.kept.find(ctx[:softwareId]).software_images
              ctx.ok(Admin::SoftwareImageSerializer.render_as_hash(images))
            end

            r.create "/softwares/:softwareId/images", summary: "Link an image of the image library to a software",
                     body: X.software_image_body, required: %i[imageId], item: X.software_image do |ctx|
              unless WarpEngine::Images.model.exists?(ctx[:imageId])
                raise Error.new(422, "Validation failed", details: { imageId: [ "is not in the image library" ] })
              end
              ctx.created(Admin::SoftwareImageSerializer.render_as_hash(add_image(ctx, ctx.attributes)))
            end

            r.create "/softwares/:softwareId/images/upload", name: :upload,
                     summary: "Upload a new image into the library and link it to a software",
                     body: X.software_image_upload_body, required: %i[file], item: X.software_image,
                     multipart: true do |ctx|
              upload = ctx[:file]
              raise Error.bad_request("file must be an uploaded file") unless upload.respond_to?(:original_filename)

              attributes = ctx.attributes("isDefault", "position").merge("file_upload" => upload)
              ctx.created(Admin::SoftwareImageSerializer.render_as_hash(add_image(ctx, attributes)))
            end

            r.get "/software_images/:id", summary: "One software image", item: X.software_image do |ctx|
              ctx.ok(Admin::SoftwareImageSerializer.render_as_hash(WarpEngine::SoftwareImage.find(ctx.id)))
            end

            r.update "/software_images/:id", summary: "Make an image the default, or move it",
                     body: S.object({ isDefault: S.boolean, position: S.integer(minimum: 0) }),
                     item: X.software_image do |ctx|
              image = WarpEngine::SoftwareImage.find(ctx.id)
              image.assign_attributes(ctx.attributes.merge("origin" => "local"))
              ctx.ok(Admin::SoftwareImageSerializer.render_as_hash(ctx.save!(image)))
            end

            r.delete "/software_images/:id", summary: "Unlink an image from its software" do |ctx|
              WarpEngine::SoftwareImage.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

        # Declares the +extras+ resource on +api+: read or replace (nested attributes)
        # what a WarpEngine::AdditionalResource holds for a software. Available when the
        # host defines any for the API.
        def extras(api)
          association = -> { S.enum(WarpEngine::AdditionalResource.api_for(:software).map(&:association)) }

          api.resource(:extras, label: "Additional resources",
                                condition: -> { WarpEngine::AdditionalResource.api_for(:software).any? }) do |r|
            r.get "/softwares/:softwareId/extras/:association", summary: "What a host-defined resource holds for a software",
                  item: X.extra, path_params: { association: association } do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              ctx.ok(extra_payload(extra(ctx[:association]), software))
            end

            r.update "/softwares/:softwareId/extras/:association",
                     summary: "Replace what a host-defined resource holds for a software (nested attributes)",
                     body: S.object({ value: { description: "An object, or an array of objects when multiple; " \
                                                            "an entry with id and _destroy removes one" } }),
                     required: %i[value], item: X.extra, path_params: { association: association } do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              extra = extra(ctx[:association])
              software.assign_attributes(extra.attributes_key => extra.nested_attributes(ctx[:value]))
              ctx.save!(software)
              ctx.ok(extra_payload(extra, software.reload))
            end
          end
        end

        # Returns the answer of a scaffold: the software (as Admin::SoftwareSerializer),
        # the repository's URLs, the pipeline id and the warnings of a
        # WarpEngine::ScaffoldService::Result.
        def scaffold_payload(result)
          repo = result.repo
          {
            software: Admin::SoftwareSerializer.render_as_hash(result.software),
            repository: { owner: repo.owner, name: repo.name, htmlUrl: repo.html_url, cloneUrl: repo.clone_url, sshUrl: repo.ssh_url },
            pipelineId: result.pipeline&.id,
            warnings: result.warnings
          }
        end

        # The serialized +software+ with the lists named in +include+ (see INCLUDES).
        # Raises a 400 Error for an unknown include.
        def software_payload(software, include)
          data = Admin::SoftwareSerializer.render_as_hash(software)
          wanted = include.to_s.split(",").map(&:strip)
          unknown = wanted - INCLUDES
          raise Error.bad_request("Unknown include: #{unknown.join(', ')}") if unknown.any?

          if wanted.include?("releases")
            data[:releases] = Admin::ReleaseSerializer.render_as_hash(software.releases.includes(:release_assets).order(created_at: :desc))
          end
          data[:images] = Admin::SoftwareImageSerializer.render_as_hash(software.software_images) if wanted.include?("images")
          data[:externalLinks] = Admin::ExternalLinkSerializer.render_as_hash(software.external_links) if wanted.include?("externalLinks")
          if wanted.include?("extras")
            data[:extras] = WarpEngine::AdditionalResource.api_for(:software).to_h { |e| [ e.association, e.value_for(software) ] }
          end
          data
        end

        # The API-enabled WarpEngine::AdditionalResource of association +name+. Raises a 404 Error.
        def extra(name)
          WarpEngine::AdditionalResource.api_for(:software).find { |e| e.association.to_s == name.to_s } ||
            raise(Error.not_found)
        end

        # The +Extra+ answer of +extra+ for +software+.
        def extra_payload(extra, software)
          { association: extra.association.to_s, multiple: extra.multiple ? true : false, value: extra.value_for(software) }
        end

        # Saves a WarpEngine::SoftwareImage with +attributes+ for the software of
        # +ctx+, placed last unless a position is given. Raises a 422 Error when invalid.
        def add_image(ctx, attributes)
          software = WarpEngine::Software.kept.find(ctx[:softwareId])
          attributes["position"] ||= software.software_images.maximum(:position).to_i + 1
          ctx.save!(WarpEngine::SoftwareImage.new(attributes.merge("software" => software)))
        end

        # The +model+ record built from +attributes+: the soft-deleted one whose
        # +keys+ match, brought back (WarpEngine::SoftDeletable.revive), or a new one.
        def revived(model, attributes, *keys)
          model.revive(attributes.slice(*keys.map(&:to_s))).tap { |record| record.assign_attributes(attributes) }
        end

        # The kept WarpEngine::Release +id+ of a kept software. Raises ActiveRecord::RecordNotFound.
        def release(id)
          WarpEngine::Release.kept.joins(:software).merge(WarpEngine::Software.kept).find(id)
        end

        # The kept WarpEngine::ReleaseAsset +id+ whose release is reachable. Raises ActiveRecord::RecordNotFound.
        def asset(id)
          asset = WarpEngine::ReleaseAsset.kept.find(id)
          release(asset.release_id)
          asset
        end

        # Raises a 422 Error when +kind+ is +html+ and the platform of +release+ is download only.
        def check_web_playable!(release, kind)
          platform = WarpEngine::Platform.for(release.software)
          return if kind.to_s != "html" || platform.nil? || platform.expected_kinds.include?("html")

          raise Error.new(422, "Validation failed",
                          details: { kind: [ "#{platform.label} releases cannot be web playable (download only)" ] })
        end

        # A LIKE pattern matching +value+ anywhere, with its wildcards escaped.
        def like(value)
          "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
        end
      end
    end
  end
end
