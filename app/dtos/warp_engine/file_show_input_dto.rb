module WarpEngine
  # Input of WarpEngine::FileService#show: +path+, the requested file path
  # relative to the file container.
  FileShowInputDto = Struct.new(:path, keyword_init: true)
end
