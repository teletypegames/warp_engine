module WarpEngine
  # The image library adapter. Software images live in a host model; the
  # adapter tells the engine how to find, list, upload and link them. The
  # default is HostModel; a host sets its own object with +image_adapter+.
  module Images
    # The default image adapter: the host model named by +image_class_name+
    # (<tt>Image</tt>), served by the host at <tt>/api/image/:id</tt>.
    class HostModel
      # The path the host serves images under.
      URL_PREFIX = "/api/image".freeze

      # Returns the configured image class name.
      def model_name
        WarpEngine.config.image_class_name
      end

      # Returns the image model class. Raises NameError when it does not exist.
      def model
        model_name.to_s.constantize
      end

      # Returns <tt>/api/image/<image_id></tt>, or +nil+ for a blank id.
      def url_for(image_id)
        image_id.present? ? "#{URL_PREFIX}/#{image_id}" : nil
      end

      # Returns a new, unsaved image record built from the uploaded file.
      def build_from_upload(upload)
        model.new(file_upload: upload)
      end

      # Returns the label of +record+ in the admin: its original file name.
      def label_for(record)
        record.original_filename
      end

      # Returns +true+ when the file of +record+ exists on disk, or when the
      # record has no +file_path+.
      def available?(record)
        return true unless record.respond_to?(:file_path)

        File.exist?(record.file_path.to_s)
      end

      # Returns <tt>[label, id]</tt> pairs of every image, by file name, for the admin picker.
      def select_options
        model.order(:original_filename).map { |record| [ label_for(record), record.id ] }
      end
    end

    class << self
      # Returns the configured image adapter; +nil+, +:host_model+ or
      # <tt>"host_model"</tt> give the shared HostModel instance.
      def adapter
        configured = WarpEngine.config.image_adapter

        case configured
        when nil, :host_model, "host_model" then host_model_adapter
        else configured
        end
      end

      # Returns +true+ when the adapter is a HostModel.
      def host_model? = adapter.is_a?(HostModel)

      # Returns the memoized HostModel instance.
      def host_model_adapter
        @host_model_adapter ||= HostModel.new
      end

      # Drops the memoized HostModel instance.
      def reset!
        @host_model_adapter = nil
      end

      # Delegates to the adapter's +model_name+.
      def model_name = adapter.model_name
      # Delegates to the adapter's +model+.
      def model = adapter.model
      # Delegates to the adapter's +url_for+.
      def url_for(image_id) = adapter.url_for(image_id)
      # Delegates to the adapter's +build_from_upload+.
      def build_from_upload(upload) = adapter.build_from_upload(upload)
      # Delegates to the adapter's +label_for+.
      def label_for(record) = adapter.label_for(record)
      # Delegates to the adapter's +available?+.
      def available?(record) = adapter.available?(record)
      # Delegates to the adapter's +select_options+.
      def select_options = adapter.select_options
    end
  end
end
