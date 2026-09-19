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
end
