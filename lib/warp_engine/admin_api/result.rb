module WarpEngine
  module AdminApi
    Result = Struct.new(:status, :data, :meta, keyword_init: true) do
      def payload
        return {} if status == 204

        { data: data, meta: meta }.compact.as_json
      end
    end
  end
end
