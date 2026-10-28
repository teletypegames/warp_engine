module WarpEngine
  module AdminApi
    module Definitions
      # The +application_tokens+ and +device_grants+ resources, both needing the
      # Scopes::TOKENS scope. A caller can never grant more than it holds.
      module Tokens
        # Short name of AdminApi::Schema.
        S = AdminApi::Schema
        # Short name of Definitions::Schemas.
        X = Schemas

        # The scope both resources need.
        TOKENS_SCOPE = AdminApi::Scopes::TOKENS

        module_function

        # Declares the +application_tokens+ and +device_grants+ resources on +api+.
        def define(api)
          application_tokens(api)
          device_grants(api)
        end

        # Declares the +application_tokens+ resource on +api+: list, get, issue (the
        # plain token is in that answer only), update, revoke (a token cannot revoke
        # itself) and rotate. All go through WarpEngine::ApplicationTokenService.
        def application_tokens(api)
          api.resource(:application_tokens, label: "Application tokens", scope: TOKENS_SCOPE) do |r|
            r.list "/application_tokens", summary: "The live application tokens", item: X.application_token,
                   filters: { state: S.enum(%w[active expired]), kind: S.enum(%w[publishing clients admin]) },
                   sort: { createdAt: :created_at, lastUsedAt: :last_used_at, name: :name },
                   default_sort: "-createdAt" do |ctx|
              ctx.list(filtered(ctx), Admin::ApplicationTokenSerializer)
            end

            r.get "/application_tokens/:id", summary: "One application token", item: X.application_token do |ctx|
              ctx.ok(Admin::ApplicationTokenSerializer.render_as_hash(token(ctx.id)))
            end

            r.create "/application_tokens", summary: "Issue a token; the plain token is in this answer only",
                     body: X.application_token_body, required: %i[name scopes], item: X.application_token do |ctx|
              scopes = Array(ctx[:scopes]).map(&:to_s).uniq
              unrestricted = ctx[:unrestricted] ? true : false
              expires_at = granted_expiry(ctx)
              authorize_grant!(ctx.principal, scopes: scopes, unrestricted: unrestricted, expires_at: expires_at)

              owner_type = owner_type_for(scopes)
              result = WarpEngine::ApplicationTokenService.new.create(
                name: ctx[:name], scopes: scopes, unrestricted: unrestricted, expires_at: expires_at,
                owner_type: owner_type, owner_id: owner_id_for(ctx, owner_type)
              )
              raise Error.invalid(result.token) unless result.created?

              ctx.created(issued_payload(result.token, result.sync))
            end

            r.update "/application_tokens/:id", summary: "Rename a token, or change its scopes or expiry",
                     body: S.object(X.application_token_body[:properties].except(:ownerId)),
                     item: X.application_token do |ctx|
              token = token(ctx.id)
              token.name = ctx[:name] if ctx.key?(:name)
              token.scopes = Array(ctx[:scopes]).map(&:to_s).uniq if ctx.key?(:scopes)
              token.unrestricted = ctx[:unrestricted] ? true : false if ctx.key?(:unrestricted)
              token.expires_at = time(ctx[:expiresAt]) if ctx.key?(:expiresAt)
              authorize_grant!(ctx.principal, scopes: Array(token.scopes), unrestricted: token.unrestricted?,
                                              expires_at: token.expires_at)
              ctx.ok(Admin::ApplicationTokenSerializer.render_as_hash(ctx.save!(token)))
            end

            r.delete "/application_tokens/:id", summary: "Revoke a token and remove it from the CI secrets" do |ctx|
              token = token(ctx.id)
              raise Error.conflict("A token cannot revoke itself here") if ctx.principal.token&.id == token.id

              WarpEngine::ApplicationTokenService.new.revoke(token)
              ctx.no_content
            end

            r.action :post, "/application_tokens/:id/rotate", name: :rotate,
                     summary: "Replace a token with a new one and push it to its pipelines",
                     item: X.application_token, status: 201 do |ctx|
              token = token(ctx.id)
              authorize_grant!(ctx.principal, scopes: Array(token.scopes), unrestricted: token.unrestricted?,
                                              expires_at: token.expires_at)
              result = WarpEngine::ApplicationTokenService.new.rotate(token)
              raise Error.conflict("Rotation failed: #{result[:reason]}") unless result[:rotated]

              ctx.created(issued_payload(result[:new_token], result[:sync_result]))
            end
          end
        end

        # Declares the read-only +device_grants+ resource on +api+, available when identity is configured.
        def device_grants(api)
          api.resource(:device_grants, label: "Device sign-ins", scope: TOKENS_SCOPE,
                                       condition: -> { WarpEngine.identity_configured? }) do |r|
            r.list "/device_grants", summary: "Device sign-ins, newest first", item: X.device_grant,
                   filters: { state: S.enum(%w[pending approved denied]) },
                   sort: { createdAt: :created_at }, default_sort: "-createdAt" do |ctx|
              scope = WarpEngine::DeviceGrant.all
              scope = case ctx[:state]
              when "pending"  then scope.pending
              when "approved" then scope.where.not(approved_at: nil)
              when "denied"   then scope.where.not(denied_at: nil)
              else scope
              end
              ctx.list(scope, Admin::DeviceGrantSerializer)
            end

            r.get "/device_grants/:id", summary: "One device sign-in", item: X.device_grant do |ctx|
              ctx.ok(Admin::DeviceGrantSerializer.render_as_hash(WarpEngine::DeviceGrant.find(ctx.id)))
            end
          end
        end

        # The active WarpEngine::ApplicationToken +id+. Raises ActiveRecord::RecordNotFound.
        def token(id) = WarpEngine::ApplicationToken.active.find(id)

        # The kept tokens matching the +state+ (active, expired) and +kind+ (publishing, clients,
        # admin) params of +ctx+.
        def filtered(ctx)
          scope = WarpEngine::ApplicationToken.kept
          scope = case ctx[:state]
          when "active"  then scope.where("expires_at IS NULL OR expires_at > ?", Time.current)
          when "expired" then scope.where(expires_at: ..Time.current)
          else scope
          end
          case ctx[:kind]
          when "clients"    then scope.where(contains(WarpEngine::ApplicationToken::CATALOG_SCOPE))
          when "admin"      then scope.where(admin_sql)
          when "publishing" then scope.where("NOT #{contains(WarpEngine::ApplicationToken::CATALOG_SCOPE)} AND NOT (#{admin_sql})")
          else scope
          end
        end

        # An SQL condition: the +scopes+ JSON column contains +scope+.
        def contains(scope)
          ActiveRecord::Base.sanitize_sql_array([ "JSON_CONTAINS(COALESCE(scopes, '[]'), ?)", scope.to_json ])
        end

        # An SQL condition: the token holds any admin scope.
        def admin_sql
          AdminApi::Scopes::ALL.map { |scope| contains(scope) }.join(" OR ")
        end

        # Raises a 403 Error when +principal+ may not grant a token with +scopes+,
        # +unrestricted+ and +expires_at+: admin scopes it lacks, unrestricted without
        # being so, or an expiry later than its own.
        def authorize_grant!(principal, scopes:, unrestricted:, expires_at:)
          wider = (scopes & AdminApi::Scopes::ALL) - principal.scopes
          raise Error.forbidden("You cannot grant admin scopes you do not hold: #{wider.join(', ')}") if wider.any?
          raise Error.forbidden("Only an unrestricted caller can grant unrestricted") if unrestricted && !principal.unrestricted?

          limit = principal.expires_at
          return if limit.nil?
          return if expires_at.present? && expires_at <= limit

          raise Error.forbidden("The token cannot outlive yours (#{limit.utc.iso8601})")
        end

        # The requested expiry of +ctx+, or the caller's own expiry when none is given.
        def granted_expiry(ctx)
          return time(ctx[:expiresAt]) if ctx.key?(:expiresAt)

          ctx.principal.expires_at
        end

        # The owner class name for a token with +scopes+: the admin owner class for admin scopes, else the engine's.
        def owner_type_for(scopes)
          admin = scopes.intersect?(AdminApi::Scopes::ALL)
          admin ? AdminApi.config.owner_class_name : WarpEngine.config.application_token_owner_class
        end

        # The owner id of the new token: the +ownerId+ param, or the caller's owner when
        # it is of +owner_type+. Raises a 422 Error otherwise.
        def owner_id_for(ctx, owner_type)
          return ctx[:ownerId] if ctx.key?(:ownerId)

          owner = ctx.principal.owner
          return owner.id if owner && owner.class.name == owner_type

          raise Error.new(422, "Validation failed", details: { ownerId: [ "is required for a #{owner_type} token" ] })
        end

        # Parses the ISO 8601 +value+, +nil+ when blank. Raises a 400 Error when malformed.
        def time(value)
          return nil if value.blank?

          Time.iso8601(value.to_s)
        rescue ArgumentError
          raise Error.bad_request("expiresAt must be an ISO 8601 time")
        end

        # The answer of an issued +token+: its serialization, the plain token and the CI +sync+ counts.
        def issued_payload(token, sync)
          Admin::ApplicationTokenSerializer.render_as_hash(token).merge(
            plainToken: token.plain_token,
            sync:       sync && { synced: Array(sync[:synced]).size, failed: Array(sync[:failed]).size }
          )
        end
      end
    end
  end
end
