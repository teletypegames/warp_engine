module CatalogHelper
  def download_path(asset)
    "/api/download?#{{ path: asset['path'].delete_prefix('/file/') }.to_query}"
  end

  def file_name(asset)
    File.basename(asset["path"])
  end
end
