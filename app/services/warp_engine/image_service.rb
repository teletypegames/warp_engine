module WarpEngine
  class ImageService
    def show(input)
      WarpEngine::Image.find(input.id)
    end
  end
end
