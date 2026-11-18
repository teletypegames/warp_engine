module WarpEngine
  module Sync
    # Decides whether a release goes to the sync servers, and which of its
    # files, from a WarpEngine::Sync::Configuration. In order: the channel,
    # the software switch, the +denied_*+ lists (softwares, categories,
    # platforms, statuses), then the +allowed_*+ lists axis by axis (software
    # name or category, platform, status): every axis with a list must
    # match, and on the first axis the name and the category are either-or.
    class Filter
      # [config] the WarpEngine::Sync::Configuration, by default WarpEngine::Sync.config
      def initialize(config = Sync.config)
        @config = config
      end

      # Returns why +release+ does not go, as a sentence, or +nil+ when it
      # goes. Does not look at whether sync is enabled.
      def reason(release)
        software = release.software
        return "the release has no software" if software.nil?

        channel = WarpEngine::Channels.for(release.version)
        return "the #{channel} channel is not in allowed_channels" unless list(:allowed_channels).include?(channel)

        switch_reason(software) || denied_reason(software) || allowed_reason(software)
      end

      # Returns +true+ when #reason has nothing against +release+.
      def allowed?(release) = reason(release).nil?

      # Returns the WarpEngine::Platform::KindSpec list of +platform+ whose
      # files go: the required ones and those the kind lists allow.
      def kind_specs(platform)
        platform.kind_specs.select { |spec| spec.required || self.class.kind_allowed?(spec.name, @config) }
      end

      # Returns +true+ when the kind lists of +config+ let the files of +kind+ go.
      def self.kind_allowed?(kind, config)
        allowed = Array(config.allowed_kinds).map(&:to_s)
        return false if Array(config.denied_kinds).map(&:to_s).include?(kind.to_s)

        allowed.empty? || allowed.include?(kind.to_s)
      end

      # Returns +true+ when +name+ matches one of +patterns+, strings in which
      # <tt>*</tt> stands for any text; the match is case-insensitive and whole.
      def self.name_matches?(name, patterns)
        Array(patterns).any? do |pattern|
          Regexp.new("\\A#{Regexp.escape(pattern.to_s).gsub('\*', '.*')}\\z", Regexp::IGNORECASE).match?(name.to_s)
        end
      end

      private

      def list(name) = Array(@config.public_send(name)).map(&:to_s)

      def switch_reason(software)
        case @config.software_switch
        when :opt_out then "switched off on the software" if software.try(:sync_enabled) == false
        when :opt_in  then "not switched on on the software" unless software.try(:sync_enabled) == true
        end
      end

      def denied_reason(software)
        return "#{software.name} is in denied_softwares" if self.class.name_matches?(software.name, list(:denied_softwares))

        { categories: software.category, platforms: software.platform, statuses: software.status }.each do |axis, value|
          return "#{value} is in denied_#{axis}" if value.present? && list(:"denied_#{axis}").include?(value.to_s)
        end
        nil
      end

      def allowed_reason(software)
        names = list(:allowed_softwares)
        categories = list(:allowed_categories)
        if (names.any? || categories.any?) && !self.class.name_matches?(software.name, names) && !categories.include?(software.category.to_s)
          return "#{software.name} is in neither allowed_softwares nor allowed_categories"
        end

        { platforms: software.platform, statuses: software.status }.each do |axis, value|
          allowed = list(:"allowed_#{axis}")
          return "#{value.presence || 'no value'} is not in allowed_#{axis}" if allowed.any? && !allowed.include?(value.to_s)
        end
        nil
      end
    end
  end
end
