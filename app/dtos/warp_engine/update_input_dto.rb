module WarpEngine
  UpdateInputDto = Struct.new(:platform, :name, :version, keyword_init: true) do
    def initialize(platform:, name:, version: nil)
      super
    end
  end
end
