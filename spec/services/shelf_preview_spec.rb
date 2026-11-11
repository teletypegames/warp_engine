require "rails_helper"
require "tmpdir"

RSpec.describe WarpEngine::ShelfPreview::C64 do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def png(width, height, path: File.join(dir, "shot.png"))
    image = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(0x6c, 0x5e, 0xb5))
    yield image if block_given?
    image.save(path)
    path
  end

  def render(path) = described_class.new(path).render.bytes

  def hires_cell_colors(bytes, cell)
    matrix = bytes[3 + cell]
    bytes[3 + 1000 + cell * 8, 8].flat_map { |row| 8.times.map { |bit| row[7 - bit] == 1 ? matrix >> 4 : matrix & 15 } }.uniq
  end

  it "reads a 384x272 frame: the screen inside the border, the border color from the frame" do
    path = png(768, 544) do |image|
      (70...470).each { |y| (64...704).each { |x| image[x, y] = ChunkyPNG::Color::BLACK } }
      (70...86).each { |y| (64...80).each { |x| image[x, y] = ChunkyPNG::Color::WHITE } }
    end

    bytes = render(path)

    expect(bytes.size).to eq(3 + 1000 + 8000)
    expect(bytes[0]).to eq(0)
    expect(bytes[2]).to eq(14)
    expect(hires_cell_colors(bytes, 0)).to eq([ 1 ])
    expect(hires_cell_colors(bytes, 1)).to eq([ 0 ])
  end

  it "draws a picture of many colors in a cell in multicolor" do
    colors = [ 0x68372b, 0x588d43, 0xb8c76f, 0x352879 ].map { |rgb| ChunkyPNG::Color.from_hex(format("#%06x", rgb)) }
    path = png(320, 200) do |image|
      200.times { |y| 320.times { |x| image[x, y] = colors[(x / 2) % 4] } }
    end

    bytes = render(path)

    expect(bytes.size).to eq(3 + 1000 + 1000 + 8000)
    expect(bytes[0]).to eq(1)
  end

  it "fits an image of another shape into the screen" do
    expect(render(png(100, 300)).size).to eq(3 + 1000 + 8000)
  end
end
