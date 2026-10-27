require "rails_helper"

RSpec.describe WarpEngine::Configuration::DSL do
  let(:config) { WarpEngine::Configuration.new }

  def apply(&block)
    described_class.apply(config, &block)
  end

  it "runs a block without a parameter, and still yields to one with a parameter" do
    previous = WarpEngine.config.site_url

    WarpEngine.configure { site_url "https://dsl.example.org" }
    expect(WarpEngine.config.site_url).to eq("https://dsl.example.org")

    WarpEngine.configure { |c| c.site_url = "https://setter.example.org" }
    expect(WarpEngine.config.site_url).to eq("https://setter.example.org")
  ensure
    WarpEngine.config.site_url = previous
  end

  it "sets the plain settings and the paired ones" do
    resolver = ->(request) { request }

    apply do
      site_url "https://example.org"
      application_tokens from: :database, owner: "AdminUser"
      image_class "Media::Picture"
      catalog_page_size 24
      subject_resolver resolver
      ignore_user_agents "warpstore/*", "bot/*"
      ignore_user_agents "warpstore/*"
    end

    expect(config.site_url).to eq("https://example.org")
    expect(config.application_token_source).to eq(:database)
    expect(config.application_token_owner_class).to eq("AdminUser")
    expect(config.image_class_name).to eq("Media::Picture")
    expect(config.catalog_page_size).to eq(24)
    expect(config.subject_resolver).to be(resolver)
    expect(config.ignored_user_agents).to eq([ "warpstore/*", "bot/*" ])
  end

  it "refuses a setting it does not know" do
    expect { apply { site "https://example.org" } }.to raise_error(NoMethodError)
  end

  describe "shelf" do
    it "writes the same definition as the hash form, once per path" do
      2.times do
        apply do
          shelf :c64, kind: "cartridge", path: "shelves/C64", extension: ".PRG", name_length: 16,
                      urls: %w[ftp://ftp.example.org/C64]
        end
      end

      expect(config.shelves).to eq([ { platform: "c64", kind: "cartridge", path: "shelves/C64", extension: ".PRG",
                                       name_length: 16, urls: %w[ftp://ftp.example.org/C64] } ])
    end

    it "refuses an unknown key" do
      expect { apply { shelf :c64, kind: "cartridge", path: "shelves/C64", folder: "x" } }
        .to raise_error(ArgumentError, /folder/)
    end
  end

  it "sets the Admin API" do
    apply do
      admin_api do
        enable
        mcp
        rate_limit 300, per: 1.minute
        public_openapi
        resources :softwares, :releases
      end
    end

    api = config.admin_api
    expect(api).to be_enabled
    expect(api).to be_mcp
    expect(api.rate_limit).to eq({ to: 300, within: 1.minute })
    expect(api).not_to be_openapi_requires_auth
    expect(api.resources).to eq(%i[softwares releases])
  end

  describe "additional_resource" do
    it "builds the descriptor with a camelCase schema, nullable enums included" do
      2.times do
        apply do
          additional_resource :seo_metadata, on: :software, label: "SEO" do
            permit :id, :locale, :og_type, :robots, :_destroy
            form { |form| form }

            api_schema do
              integer :id
              string  :locale, enum: %w[en hu]
              string  :og_type, null: true
              string  :robots, null: true, enum: [ "noindex, follow" ]
            end
          end
        end
      end

      expect(config.additional_resources.size).to eq(1)
      resource = config.additional_resources.first
      expect(resource).to have_attributes(subject: :software, association: :seo_metadata, label: "SEO", multiple: true,
                                          permitted: %i[id locale og_type robots _destroy])
      expect(resource.render(:builder)).to eq(:builder)
      expect(resource.api_schema).to eq(
        type:       "object",
        properties: {
          id:     { type: "integer" },
          locale: { type: "string", enum: %w[en hu] },
          ogType: { type: [ "string", "null" ] },
          robots: { type: [ "string", "null" ], enum: [ nil, "noindex, follow" ] }
        }
      )
    end

    it "needs a form" do
      expect { apply { additional_resource(:notes, on: :software, label: "Notes") { permit :id } } }
        .to raise_error(ArgumentError, /fields/)
    end
  end

  describe "ci" do
    it "names an adapter without a block" do
      apply { ci :none }

      expect(config.ci_adapter).to eq(:none)
    end

    it "builds the adapter with the shared tools image, which a platform may override" do
      apply do
        ci :woodpecker do
          url       "https://ci.example.org"
          api_token "secret"
          tools     "registry.example/tools:1"

          platform :godot, builder: "registry.example/godot:4"
          platform :dos,   builder: "registry.example/dos", tools: "registry.example/tools:2", forge_release: true
        end
      end

      adapter = config.ci_adapter
      expect(adapter).to be_a(WarpEngine::CI::Woodpecker::Adapter)
      expect(adapter.url).to eq("https://ci.example.org")
      expect(adapter).to be_configured
      expect(adapter.platforms).to eq(
        "godot" => { tools: "registry.example/tools:1", builder: "registry.example/godot:4" },
        "dos"   => { tools: "registry.example/tools:2", builder: "registry.example/dos", forge_release: true }
      )
    end

    it "builds a GitLab adapter" do
      apply { ci(:gitlab) { webhook_secret "x" } }

      expect(config.ci_adapter).to be_a(WarpEngine::CI::Gitlab::Adapter)
    end

    {
      "an unknown adapter"          => proc { ci(:jenkins) { url "x" } },
      "a setting of another server" => proc { ci(:gitlab) { repo_owner "x" } },
      "an unknown platform key"     => proc { ci(:woodpecker) { platform :godot, builder: "x", image: "y" } },
      "a platform without builder"  => proc { ci(:woodpecker) { platform :godot, builder: nil } }
    }.each do |label, block|
      it "refuses #{label}" do
        expect { apply(&block) }.to raise_error(ArgumentError)
      end
    end
  end
end
