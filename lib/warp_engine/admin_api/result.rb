module WarpEngine
  module AdminApi
    # What an operation handler returns: the HTTP +status+, the +data+ of the
    # answer and an optional +meta+ hash (pagination). Built by Context#ok,
    # Context#created and Context#no_content.
    Result = Struct.new(:status, :data, :meta, keyword_init: true) do
      # The JSON body of the answer: <tt>{ data:, meta: }</tt> without the nil keys, or an
      # empty hash for a 204 answer.
      def payload
        return {} if status == 204

        { data: data, meta: meta }.compact.as_json
      end
    end
  end
end
