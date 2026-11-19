module WarpEngine
  module Local
    # The registry of the local component classes
    # (WarpEngine::Local::Component subclasses). The engine registers
    # WarpEngine::Local::Components::Gitea and
    # WarpEngine::Local::Components::Woodpecker; a host may add its own.
    module Components
      module_function

      # Registers +klass+ under its key; a later class with the same key replaces it.
      def register(klass)
        registry[klass.key.to_s] = klass
      end

      # Returns the component classes, in registration order.
      def classes = registry.values

      # Returns the class with +key+, or +nil+.
      def find(key) = registry[key.to_s]

      # Returns the classes with +role+.
      def for_role(role) = classes.select { |klass| klass.role.to_s == role.to_s }

      # Returns the registry Hash.
      def registry = @registry ||= {}
    end
  end
end
