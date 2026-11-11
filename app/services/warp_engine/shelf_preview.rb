require "chunky_png"

module WarpEngine
  # Shelf previews: a picture of each title in a form its shelf's client can
  # show by itself, written next to the title (see WarpEngine::ShelfService).
  # A shelf asks for one with its +preview+ key; FORMATS maps the key to the
  # renderer.
  module ShelfPreview
    # Returns the renderer class of +format+, or +nil+.
    def self.for(format) = FORMATS[format.to_s]

    # A C64 bitmap made from a PNG, the preview format of WARP64U:
    #
    #   byte 0      mode: 0 hires, 1 multicolor
    #   byte 1      background color (multicolor)
    #   byte 2      border color
    #   1000 bytes  screen matrix
    #   1000 bytes  color RAM (multicolor only)
    #   8000 bytes  bitmap, 8 bytes a cell, cells row by row
    #
    # The image is read as a C64 frame when its shape is near one: 384x272 with
    # the border (a VICE screenshot) when the border band is of one color, else
    # 320x200 without the border; anything else is fitted into the screen. Every pixel takes the nearest of the 16 colors,
    # then the picture is drawn both in hires (two colors in each 8x8 cell) and
    # in multicolor (a shared background and three colors in each 4x8 cell, at
    # half the width); the one closer to the image wins.
    class C64
      # The file extension of the preview on the shelf.
      EXTENSION = ".PVW".freeze
      # The width of the screen, in hires pixels.
      WIDTH = 320
      # The height of the screen, in pixels.
      HEIGHT = 200
      # The width of a screenshot with the border (a VICE PAL frame).
      FRAME_WIDTH = 384
      # The height of a screenshot with the border.
      FRAME_HEIGHT = 272
      # The first screen column in such a frame.
      SCREEN_LEFT = 32
      # The first screen line in such a frame.
      SCREEN_TOP = 35
      # How far the aspect ratio of an image may be from a frame's to be read as one.
      SHAPE_TOLERANCE = 0.12
      # The share of the border samples that must have the color of the most
      # common one for a frame to count as one with a border.
      BORDER_UNIFORMITY = 0.95
      # The 16 colors (Pepto's palette), as RGB.
      PALETTE = [
        [ 0x00, 0x00, 0x00 ], [ 0xff, 0xff, 0xff ], [ 0x68, 0x37, 0x2b ], [ 0x70, 0xa4, 0xb2 ],
        [ 0x6f, 0x3d, 0x86 ], [ 0x58, 0x8d, 0x43 ], [ 0x35, 0x28, 0x79 ], [ 0xb8, 0xc7, 0x6f ],
        [ 0x6f, 0x4f, 0x25 ], [ 0x43, 0x39, 0x00 ], [ 0x9a, 0x67, 0x59 ], [ 0x44, 0x44, 0x44 ],
        [ 0x6c, 0x6c, 0x6c ], [ 0x9a, 0xd2, 0x84 ], [ 0x6c, 0x5e, 0xb5 ], [ 0x95, 0x95, 0x95 ]
      ].freeze
      # The squared distance of every pair of colors.
      DISTANCE = PALETTE.map { |a| PALETTE.map { |b| a.zip(b).sum { |x, y| (x - y)**2 } } }.freeze
      # How many of the most frequent colors of a cell are tried.
      CANDIDATES = 4

      # One way of drawing the picture: its total +error+ and its +bytes+.
      Picture = Struct.new(:error, :bytes)

      # [path] the PNG file
      def initialize(path)
        @path = path
      end

      # Returns the preview as a binary String. Raises ChunkyPNG::Exception on
      # a file that is not a PNG.
      def render
        image = ChunkyPNG::Image.from_file(@path)
        @border = nearest(border_sample(image))
        @pixels = sample(image)
        [ hires, multicolor ].min_by(&:error).bytes
      end

      private

      def shape(image) = image.width.to_f / image.height

      def near?(ratio, width, height) = (ratio / (width.to_f / height) - 1).abs < SHAPE_TOLERANCE

      def bordered?(image)
        return @bordered if defined?(@bordered)

        @bordered = near?(shape(image), FRAME_WIDTH, FRAME_HEIGHT) && begin
          samples = border_points.map { |x, y| nearest(image[x * image.width / FRAME_WIDTH, y * image.height / FRAME_HEIGHT]) }
          samples.tally.values.max >= samples.size * BORDER_UNIFORMITY
        end
      end

      def border_points
        across = (0...FRAME_WIDTH).step(8).flat_map { |x| [ [ x, 8 ], [ x, SCREEN_TOP - 8 ], [ x, FRAME_HEIGHT - 8 ] ] }
        down = (0...FRAME_HEIGHT).step(8).flat_map { |y| [ [ 8, y ], [ FRAME_WIDTH - 8, y ] ] }
        across + down
      end

      def border_sample(image)
        return image[0, 0] unless bordered?(image)

        image[image.width * 8 / FRAME_WIDTH, image.height * 8 / FRAME_HEIGHT]
      end

      # The color index of every screen pixel, row by row, sampled at the
      # pixel centers.
      def sample(image)
        ratio = shape(image)
        if bordered?(image)
          grid(image, image.width.to_f / FRAME_WIDTH, image.height.to_f / FRAME_HEIGHT, SCREEN_LEFT, SCREEN_TOP)
        elsif near?(ratio, WIDTH, HEIGHT)
          grid(image, image.width.to_f / WIDTH, image.height.to_f / HEIGHT, 0, 0)
        else
          fitted(image)
        end
      end

      def grid(image, step_x, step_y, left, top)
        cache = {}
        Array.new(WIDTH * HEIGHT) do |i|
          x = ((i % WIDTH + left + 0.5) * step_x).floor.clamp(0, image.width - 1)
          y = ((i / WIDTH + top + 0.5) * step_y).floor.clamp(0, image.height - 1)
          color = image[x, y]
          cache[color] ||= nearest(color)
        end
      end

      def fitted(image)
        scale = [ WIDTH.to_f / image.width, HEIGHT.to_f / image.height ].min
        width = (image.width * scale).round
        height = (image.height * scale).round
        left = (WIDTH - width) / 2
        top = (HEIGHT - height) / 2
        background = nearest(image[0, 0])
        cache = {}
        Array.new(WIDTH * HEIGHT) do |i|
          x = i % WIDTH - left
          y = i / WIDTH - top
          next background if x.negative? || y.negative? || x >= width || y >= height

          color = image[((x + 0.5) / scale).floor.clamp(0, image.width - 1), ((y + 0.5) / scale).floor.clamp(0, image.height - 1)]
          cache[color] ||= nearest(color)
        end
      end

      def nearest(color)
        rgb = [ ChunkyPNG::Color.r(color), ChunkyPNG::Color.g(color), ChunkyPNG::Color.b(color) ]
        PALETTE.each_index.min_by { |index| PALETTE[index].zip(rgb).sum { |a, b| (a - b)**2 } }
      end

      # The 64 pixels of cell +cx+, +cy+, row by row.
      def cell(cx, cy)
        Array.new(64) { |i| @pixels[(cy * 8 + i / 8) * WIDTH + cx * 8 + i % 8] }
      end

      def candidates(pixels, leave_out = nil)
        pixels.tally.except(leave_out).sort_by { |color, count| [ -count, color ] }.first(CANDIDATES).map(&:first)
      end

      def each_cell
        25.times { |cy| 40.times { |cx| yield cx, cy } }
      end

      # Two colors in each 8x8 cell: the pair of the cell's frequent colors
      # that misses the least; a set bit takes the high nibble color.
      def hires
        error = 0
        matrix = []
        bitmap = []
        each_cell do |cx, cy|
          pixels = cell(cx, cy)
          colors = candidates(pixels)
          pairs = colors.product(colors).select { |a, b| a <= b }
          fore, back = pairs.min_by { |a, b| pixels.sum { |p| [ DISTANCE[p][a], DISTANCE[p][b] ].min } }
          matrix << ((fore << 4) | back)
          pixels.each_slice(8) do |row|
            byte = 0
            row.each { |p| byte = (byte << 1) | (DISTANCE[p][fore] < DISTANCE[p][back] ? 1 : 0) }
            bitmap << byte
          end
          error += pixels.sum { |p| [ DISTANCE[p][fore], DISTANCE[p][back] ].min }
        end
        Picture.new(error, [ 0, 0, @border ].pack("C*") + matrix.pack("C*") + bitmap.pack("C*"))
      end

      # A shared background (the most frequent color) and three colors in each
      # 4x8 cell; a multicolor pixel covers two pixels of the image.
      def multicolor
        background = @pixels.tally.max_by { |color, count| [ count, -color ] }.first
        error = 0
        matrix = []
        colors_ram = []
        bitmap = []
        each_cell do |cx, cy|
          pixels = cell(cx, cy)
          choices = candidates(pixels, background)
          sets = choices.size <= 3 ? [ choices ] : choices.combination(3).to_a
          best = sets.min_by { |set| multicolor_error(pixels, [ background ] + set) }
          palette = ([ background ] + best + [ background ] * 3).first(4)
          matrix << ((palette[1] << 4) | palette[2])
          colors_ram << palette[3]
          pixels.each_slice(8) do |row|
            byte = 0
            row.each_slice(2) do |a, b|
              code = (0..3).min_by { |k| DISTANCE[a][palette[k]] + DISTANCE[b][palette[k]] }
              byte = (byte << 2) | code
            end
            bitmap << byte
          end
          error += multicolor_error(pixels, palette)
        end
        Picture.new(error, [ 1, background, @border ].pack("C*") + matrix.pack("C*") + colors_ram.pack("C*") + bitmap.pack("C*"))
      end

      def multicolor_error(pixels, palette)
        pixels.each_slice(2).sum { |a, b| palette.map { |c| DISTANCE[a][c] + DISTANCE[b][c] }.min }
      end
    end

    # The preview formats a shelf may name.
    FORMATS = { "c64" => C64 }.freeze
  end
end
