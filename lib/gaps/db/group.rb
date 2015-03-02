require 'chalk-log'

module Gaps::DB
  class Group < Base
    set_collection_name 'group'

    key :group_email, String
    key :description, String
    key :direct_members_count, String

    key :deleted, Boolean, default: false

    key :config, Hash # config JSON tag in description
    key :group_settings, Hash

    key :category, String # legacy

    def self.build_index
      self.ensure_index(:group_email, unique: true)
    end

    def self.thread_pool
      @thread_pool ||= Thread::Pool.new(configatron.cache.pool_size)
    end

    def category
      self.config['category'] || super
    end

    def category=(category)
      self.config['category'] = category
    end

    ### API methods

    # Could technically have multiple @s, I guess, but whatever.
    def group_name
      group_email.split('@')[0]
    end

    def page
      "https://groups.google.com/a/#{configatron.info.domain}/forum/?fromgroups#!forum/#{CGI.escape(group_name)}"
    end

    def describe
      [group_email, description].compact.join(': ')
    end

    def to_s
      "<Group: group_email=#{group_email.inspect}>"
    end

    def notify_creation
      Gaps::Email.send_email(
        :to => configatron.notify.to,
        :from => configatron.notify.from,
        :subject => "[gaps] New mailing list created: #{group_email}",
        :body => <<EOF
A new mailing list was just created:

  #{describe}

You can subscribe to this list at:

  #{configatron.gaps_url}/subs#lst-#{group_email}

You can view more details about this group at:

  #{page}
EOF
        )
    end

    # Parse the description into freeform-text and a config hash
    def parse_description
      desc = self.description
      text, tag = split_last_line(desc)

      begin
        config = JSON.parse(tag)
        unless config.kind_of?(Hash)
          log.error("Ignoring non-hash JSON tag", text: text, tag: tag, group_email: group_email)
          text = desc
          config = {}
        end
      rescue JSON::ParserError
        text = desc
        config = {}
      end

      [text, config]
    end

    def split_last_line(str)
      lines = str.split("\n")
      [lines[0...-1].join("\n"), lines[-1] || '']
    end

    # Regenerate the description, using the group's parsed config hash
    # in place of the existing config tag.
    def generate_description
      text, _ = parse_description
      parts = []
      parts << text if text.length > 0
      parts << JSON.generate(config) if config && config.length > 0
      parts.join("\n")
    end

    def default_filter_label
      if self.group_email =~ /\A(.+)-bots(-[^@]+)?@/
        label = $1 + '/bots'
      elsif self.group_email =~ /\A(.+)-(archive|open|team)@/
        label = $1
      else
        label = self.group_name
      end
      label.gsub(%r{\Aall(/.*)?\z}) { "everyone#{$1}" }
    end

    # Updates the properties on this group object. If no groupinfo is
    # provided, will automatically retrieve from API.
    def update_config(groupinfo, user=User.lister)
      if configatron.populate_group_settings
        begin
          settings = user.requestor.get_group_settings(self.group_email)
        rescue Google::APIClient::ServerError => e
          # This API seems to be flaky sometimes, so swallow error and
          # continue on.
          log.error("Error requesting group settings: #{e.message} (#{e.class})", group_email: self.group_email)
        rescue Google::APIClient::ClientError => e
          # Be helpful to people
          if e.message =~ /Domain cannot use Api, Groups service is not installed/
            e.message << ' (HINT: you need to be on Google Groups for Business to use the Groups service. You can turn off groups settings population by disabling the `populate_group_settings` key.)'
          end
          raise
        else
          self.group_settings = settings
        end
      end

      groupinfo ||= user.requestor.get_group(self.group_email)

      self.description = groupinfo.fetch('description')
      self.direct_members_count = groupinfo.fetch('directMembersCount')

      _, config = parse_description
      # Keep the existing category if one set
      config['category'] ||= self.category || self.group_email.split(/[@-]/)[0]

      self.config = config
      self.deleted = false
    end

    def memberships
      User.lister.requestor.membership_list_for_group(self.group_email)
    end

    def hidden?
      if configatron.permissions.privacy_settings.gaps_scheme &&
          custom_hidden?
        return true
      end

      if configatron.permissions.privacy_settings.api_scheme &&
          group_settings_hidden?
        return true
      end

      return false
    end

    def custom_hidden?
      # Our custom permissioning scheme (probably going to deprecate
      # this, but Stripe's found it convenient while we had limited
      # permissioning needs).
      self.config['display'] ||
        self.group_email.start_with?('acl-') ||
        self.group_email.start_with?('private-')
    end

    # Is it hidden according to the Google Groups settings API?
    def group_settings_hidden?
      settings = self.group_settings

      !('true' == settings['showInGroupDirectory'] &&
        ['ANYONE_CAN_JOIN', 'ALL_IN_DOMAIN_CAN_JOIN'].include?(settings['whoCanJoin']) &&
        ['ANYONE_CAN_VIEW', 'ALL_IN_DOMAIN_CAN_VIEW'].include?(settings['whoCanViewGroup']))
    end

    def move_category(new_category)
      if configatron.persist_config_to_group
        # Make sure we have an up-to-date description
        update_config(nil)
        # Set the new category
        self.config['category'] = new_category
        # Update the description currently stored on the group
        self.description = generate_description
        # Save it back via the API
        persist_description
      else
        self.category = new_category
      end

      save!
    end

    def persist_description
      User.lister.requestor.update_group_description(
        group_email, self.description
        )
    end

    def self.boot
      return unless User.lister

      if Gaps::DB::State.initialized?
        log.info('Warming group cache on boot')
        warm_transitive_closure_cache
      else
        log.info('Slurping down group list for the first time')
        refresh
      end
    end

    def self.background_refresh
      self.thread_pool.process do
        self.refresh
      end
    end

    def self.refresh_if_able
      refresh if User.lister
    end

    def self.refresh
      log.info('Doing a full refresh of all groups')

      initialized = Gaps::DB::State.initialized?

      user = User.lister
      futures = user.requestor.group_list.map do |groupinfo|
        Thread.future(thread_pool) do
          email = groupinfo.fetch('email')
          # Kind of janky, but you get back deleted groups from the API
          # as <name>-deleted-4301b@
          next if email =~ /-deleted/

          group = find_or_initialize_by_group_email(email)
          group.update_config(groupinfo, user)

          if group.new_record?
            log.info("Creating a new group", group: group)
            # Don't notify about display-restricted lists
            group.notify_creation if initialized && !group.hidden?
            group.save!
          elsif group.changed?
            log.info("Updating existing group", group: group)
            group.save!
          end

          group._id
        end
      end

      # Could also store a refreshed_at prop in the DB, basically
      # doing mark-sweep. But this is simpler.
      live_groups = Set.new(futures.map(&:~))

      # Garbage-collect any groups that don't exist anymore
      self.find_each(deleted: false) do |group|
        next if live_groups.include?(group._id)
        log.info('Deleting group', id: group._id, group_email: group.group_email)
        collection.update({'_id' => group._id}, {'$set' => {deleted: true}})
      end

      warm_transitive_closure_cache

      Gaps::DB::State.mark_initialized unless initialized
    end

    def self.warm_transitive_closure_cache
      futures = []

      self.find_each(deleted: false) do |group|
        futures << Thread.future(self.thread_pool) do
          group.memberships
        end
      end

      # Wait on all futures
      futures.each(&:~)
      nil
    end

    def self.viewable(user)
      self.find_each(:deleted => false).reject do |group|
        group.hidden?
      end
    end

    # Eventually, make these replicate Google's permissioning logic.
    def viewable?(user)
      !deleted && !hidden?
    end

    def self.categorized(user, subscribed_only=false)
      groups = self.viewable(user).sort_by {|group| group.group_email}
      if subscribed_only
        groups.delete_if do |grp|
          !user.group_member?(grp) && !user.group_member_through_list(grp)
        end
      end
      categories = groups.group_by {|group| group.category}
      categories.sort do |(a, _), (b, _)|
        if a == '' && b != ''
          1
        elsif a != '' && b == ''
          -1
        else
          a <=> b
        end
      end
    end
  end
end
