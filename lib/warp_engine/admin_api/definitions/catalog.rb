module WarpEngine
  module AdminApi
    module Definitions
      module Catalog
        S = AdminApi::Schema
        X = Schemas

        INCLUDES = %w[releases images externalLinks extras].freeze

        module_function

        def define(api)
          softwares(api)
          releases(api)
          release_assets(api)
          external_links(api)
          software_images(api)
          extras(api)
        end

        def softwares(api)
          api.resource(:softwares, label: "Softwares") do |r|
            r.list "/softwares", summary: "List the softwares", item: X.software,
                   filters: {
                     name:        S.string("Name contains"),
                     title:       S.string("Title contains"),
                     author:      S.string("Author contains"),
                     platform:    S.enum(WarpEngine::Platform::NAMES),
                     status:      S.string("A status key"),
                     category:    S.string("A category key"),
                     highlighted: S.boolean,
                     q:           S.string("Matched against title and name")
                   },
                   sort: { title: :title, name: :name, createdAt: :created_at, updatedAt: :updated_at } do |ctx|
              scope = WarpEngine::Software.kept
              %i[name title author].each do |column|
                scope = scope.where("softwares.#{column} LIKE ?", like(ctx[column])) if ctx[column].present?
              end
              scope = scope.where(platform: ctx[:platform]) if ctx[:platform].present?
              scope = scope.where(status: ctx[:status]) if ctx[:status].present?
              scope = scope.where(category: ctx[:category]) if ctx[:category].present?
              scope = scope.where(highlighted: ctx[:highlighted]) if ctx.key?(:highlighted)
              ctx.list(scope.search(ctx[:q]), Admin::SoftwareSerializer)
            end

            r.get "/softwares/:id", summary: "One software, optionally with what belongs to it", item: X.software,
                  query: { include: S.string("Comma-separated: #{INCLUDES.join(', ')}") } do |ctx|
              ctx.ok(software_payload(WarpEngine::Software.kept.find(ctx.id), ctx[:include]))
            end

            r.create "/softwares", summary: "Create a software", body: X.software_body,
                     required: %i[name title platform], item: X.software do |ctx|
              software = ctx.save!(WarpEngine::Software.new(ctx.attributes))
              ctx.created(Admin::SoftwareSerializer.render_as_hash(software))
            end

            r.update "/softwares/:id", summary: "Change a software", body: X.software_body, item: X.software do |ctx|
              software = WarpEngine::Software.kept.find(ctx.id)
              software.assign_attributes(ctx.attributes)
              ctx.ok(Admin::SoftwareSerializer.render_as_hash(ctx.save!(software)))
            end

            r.delete "/softwares/:id", summary: "Delete a software with its releases" do |ctx|
              WarpEngine::Software.kept.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

        def releases(api)
          api.resource(:releases, label: "Releases") do |r|
            r.list "/softwares/:softwareId/releases", summary: "The releases of a software", item: X.release,
                   sort: { createdAt: :created_at, version: :version }, default_sort: "-createdAt" do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              ctx.list(software.releases.includes(:release_assets), Admin::ReleaseSerializer)
            end

            r.create "/softwares/:softwareId/releases", summary: "Add a release", body: X.release_body,
                     required: %i[version], item: X.release do |ctx|
              software = WarpEngine::Software.kept.find(ctx[:softwareId])
              release = ctx.save!(WarpEngine::Release.new(ctx.attributes.merge("software" => software)))
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

            r.delete "/releases/:id", summary: "Delete a release with its assets" do |ctx|
              release(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

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
              asset = ctx.save!(WarpEngine::ReleaseAsset.new(ctx.attributes.merge("release" => release)))
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

            r.delete "/assets/:id", summary: "Delete an asset" do |ctx|
              asset(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

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

            r.delete "/external_links/:id", summary: "Delete an external link" do |ctx|
              WarpEngine::ExternalLink.kept.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

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
              image.assign_attributes(ctx.attributes)
              ctx.ok(Admin::SoftwareImageSerializer.render_as_hash(ctx.save!(image)))
            end

            r.delete "/software_images/:id", summary: "Unlink an image from its software" do |ctx|
              WarpEngine::SoftwareImage.find(ctx.id).destroy!
              ctx.no_content
            end
          end
        end

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

        def extra(name)
          WarpEngine::AdditionalResource.api_for(:software).find { |e| e.association.to_s == name.to_s } ||
            raise(Error.not_found)
        end

        def extra_payload(extra, software)
          { association: extra.association.to_s, multiple: extra.multiple ? true : false, value: extra.value_for(software) }
        end

        def add_image(ctx, attributes)
          software = WarpEngine::Software.kept.find(ctx[:softwareId])
          attributes["position"] ||= software.software_images.maximum(:position).to_i + 1
          ctx.save!(WarpEngine::SoftwareImage.new(attributes.merge("software" => software)))
        end

        def release(id)
          WarpEngine::Release.kept.joins(:software).merge(WarpEngine::Software.kept).find(id)
        end

        def asset(id)
          asset = WarpEngine::ReleaseAsset.kept.find(id)
          release(asset.release_id)
          asset
        end

        def check_web_playable!(release, kind)
          platform = WarpEngine::Platform.find(release.software&.platform)
          return if kind.to_s != "html" || platform.nil? || platform.expected_kinds.include?("html")

          raise Error.new(422, "Validation failed",
                          details: { kind: [ "#{platform.label} releases cannot be web playable (download only)" ] })
        end

        def like(value)
          "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
        end
      end
    end
  end
end
