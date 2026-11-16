require "rails_helper"

RSpec.describe WarpEngine::Images do
  after { WarpEngine.config.image_adapter = nil }

  describe "the default adapter" do
    it "is the host model named in the configuration" do
      expect(described_class.model_name).to eq("Image")
      expect(described_class.model).to eq(Image)
    end

    it "serves images from the address the clients have always used" do
      expect(described_class.url_for(7)).to eq("/api/image/7")
      expect(described_class.url_for(nil)).to be_nil
    end

    it "offers the host's images to an admin select" do
      image = create(:image, original_filename: "cover.png")

      expect(described_class.select_options).to include([ "cover.png", image.id ])
    end

    it "finds the file of an image, when it is there" do
      FileUtils.mkdir_p(Image.upload_path)
      image = create(:image, filename: "present-#{SecureRandom.hex(4)}.png")
      File.binwrite(image.file_path, "PNG")
      missing = create(:image)

      expect(described_class.file_path_for(image.id)).to eq(image.file_path)
      expect(described_class.file_path_for(missing.id)).to be_nil
      expect(described_class.file_path_for(nil)).to be_nil
    ensure
      FileUtils.rm_f(image.file_path) if image
    end

    it "builds a host image from an upload" do
      expect(described_class.build_from_upload(nil)).to be_a(Image)
    end
  end

  describe "a host adapter" do
    it "decides where an image is served from" do
      WarpEngine.config.image_adapter = Class.new do
        def url_for(image_id) = "https://cdn.example.com/#{image_id}.png"
      end.new

      expect(described_class.url_for(9)).to eq("https://cdn.example.com/9.png")
      expect(described_class.file_path_for(9)).to be_nil
    end
  end

  it "links the catalog to the host's image model" do
    expect(WarpEngine::SoftwareImage.reflect_on_association(:image).klass).to eq(Image)
  end

  it "puts the adapter URL in the catalog payload" do
    software = create(:software)
    image    = create(:image)
    WarpEngine::SoftwareImage.create!(software: software, image_id: image.id, is_default: true)

    payload = WarpEngine::SoftwareSerializer.render_as_hash(software.reload)

    expect(payload[:imageUrl]).to eq("/api/image/#{image.id}")
  end
end
