module WarpEngine
  module Sync
    # Decides whether a release passes a sync direction, and which of its
    # files, from the direction's settings (WarpEngine::Sync::Outbound or
    # WarpEngine::Sync::Inbound). In order: the channel,
    # the software switch, the +denied_*+ lists (softwares, categories,
    # platforms, statuses), then the +allowed_*+ lists axis by axis (software
    # name or category, platform, status): every axis with a list must
    # match, and on the first axis the name and the category are either-or.
    # A filter #for a WarpEngine::SyncPeer also holds back the channels the
    # peer leaves out of its own +allowed_channels+.
    class Filter
      # [config] the direction's settings, by default WarpEngine::Sync.config.outbound
      # [peer]   the WarpEngine::SyncPeer whose channels narrow it, or +nil+
      def initialize(config = Sync.config.outbound, peer: nil)
        @config = config
        @peer = peer
      end

      # Returns a filter with the same settings, narrowed to the channels of
      # +peer+ (a WarpEngine::SyncPeer, or +nil+ for none).
      def for(peer) = self.class.new(@config, peer: peer)

      # Returns why +release+ does not pass, as a sentence, or +nil+ when it
      # does. Does not look at whether the direction is enabled.
      def reason(release) = reason_for(release.software, release.version)

      # Returns why the +version+ of +software+ (anything answering +name+,
      # +platform+, +category+ and +status+) does not pass, or +nil+.
      def reason_for(software, version)
        return "the release has no software" if software.nil?

        channel = WarpEngine::Channels.for(version)
        return "the #{channel} channel is not in allowed_channels" unless list(:allowed_channels).include?(channel)
        return "the #{channel} channel is not in #{@peer.label}'s channels" if peer_refuses?(channel)

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
        allowed = Array(config.try(:allowed_kinds)).map(&:to_s)
        return false if Array(config.try(:denied_kinds)).map(&:to_s).include?(kind.to_s)

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

      def peer_refuses?(channel)
        channels = @peer.respond_to?(:channels) ? @peer.channels : []
        channels.any? && !channels.include?(channel)
      end

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
