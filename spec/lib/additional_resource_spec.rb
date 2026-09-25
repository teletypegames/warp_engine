require "rails_helper"

RSpec.describe WarpEngine::AdditionalResource do
  let(:descriptor) do
    described_class.new(
      subject: :software,
      association: :notes,
      label: "Notes",
      permitted: %i[id body _destroy],
      fields: ->(form) { form }
    )
  end

  around do |example|
    previous = WarpEngine.config.additional_resources
    WarpEngine.config.additional_resources = [ descriptor ]
    example.run
    WarpEngine.config.additional_resources = previous
  end

  it "defaults to no additional resources" do
    expect(WarpEngine::Configuration.new.additional_resources).to eq([])
  end

  it "names the nested attributes key after the association" do
    expect(descriptor.attributes_key).to eq(:notes_attributes)
    expect(descriptor.permitted_params).to eq({ notes_attributes: %i[id body _destroy] })
  end

  it "collects the descriptors of one subject" do
    expect(described_class.for(:software)).to eq([ descriptor ])
    expect(described_class.for(:release)).to eq([])
    expect(described_class.permitted_params_for(:software)).to eq([ { notes_attributes: %i[id body _destroy] } ])
  end

  it "hands the form builder to the host" do
    expect(descriptor.render(:builder)).to eq(:builder)
  end

  it "refuses a descriptor that cannot render" do
    expect {
      described_class.new(subject: :software, association: :notes, label: "Notes", permitted: [], fields: nil)
    }.to raise_error(ArgumentError)
  end

  describe "in the Admin API" do
    let(:software) { create(:software) }

    it "stays out of the API without a schema" do
      expect(descriptor.api?).to be(false)
      expect(described_class.api_for(:software)).to eq([])
    end

    it "serializes the permitted attributes in camelCase unless the host serializes" do
      link = software.external_links.create!(label: "Repo", url: "https://example.org")
      extra = described_class.new(subject: :software, association: :external_links, label: "Links",
                                  permitted: %i[id label url _destroy], fields: ->(form) { form },
                                  api_schema: { type: "object" })

      expect(extra.value_for(software)).to eq([ { "id" => link.id, "label" => "Repo", "url" => "https://example.org" } ])

      custom = described_class.new(subject: :software, association: :external_links, label: "Links",
                                   permitted: %i[id label], fields: ->(form) { form }, api_schema: { type: "object" },
                                   api_serializer: ->(record) { { name: record.label } })
      expect(custom.value_for(software)).to eq([ { "name" => "Repo" } ])
    end

    it "turns an API value into nested attributes, keeping only the permitted keys" do
      expect(descriptor.nested_attributes([ { "id" => 1, "body" => "x", "sneaky" => true, "_destroy" => true } ]))
        .to eq([ { "id" => 1, "body" => "x", "_destroy" => true } ])
      expect { descriptor.nested_attributes({ "body" => "x" }) }.to raise_error(ArgumentError)
    end
  end
end
