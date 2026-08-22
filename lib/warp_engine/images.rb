module WarpEngine

  module Images

    class HostModel
      URL_PREFIX = "/api/image".freeze

      def model_name
        WarpEngine.config.image_class_name
      end

      def model
        model_name.to_s.constantize
      end

      def url_for(image_id)
        image_id.present? ? "#{URL_PREFIX}/#{image_id}" : nil
      end

      def build_from_upload(upload)
        model.new(file_upload: upload)
      end

      def label_for(record)
        record.original_filename
      end

      def available?(record)
        return true unless record.respond_to?(:file_path)

        File.exist?(record.file_path.to_s)
      end

      def select_options
        model.order(:original_filename).map { |record| [ label_for(record), record.id ] }
      end
    end

    class << self
      def adapter
        configured = WarpEngine.config.image_adapter

        case configured
        when nil, :host_model, "host_model" then host_model_adapter
        else configured
        end
      end

      def host_model? = adapter.is_a?(HostModel)

      def host_model_adapter
        @host_model_adapter ||= HostModel.new
      end

      def reset!
        @host_model_adapter = nil
      end

      def model_name = adapter.model_name
      def model = adapter.model
      def url_for(image_id) = adapter.url_for(image_id)
      def build_from_upload(upload) = adapter.build_from_upload(upload)
      def label_for(record) = adapter.label_for(record)
      def available?(record) = adapter.available?(record)
      def select_options = adapter.select_options
    end
  end
end
