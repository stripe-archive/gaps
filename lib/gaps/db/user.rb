require 'thread'

module Gaps::DB
  class User < Base
    class GrantExpired < StandardError; end
    class InvalidUser < StandardError; end

    set_collection_name 'user'

    key :google_id, String
    key :name, String
    key :email, String
    key :admin, Boolean, default: false
    key :image_url, String

    key :refresh_token, String
    key :access_token, String
    key :expires_in, Integer
    key :issued_at, Integer

    key :refreshable, Boolean, :default => false
    key :grant_type, String, :default => 'normal'

    key :alternate_emails, Array, :default => []
    key :filters, Hash, :default => {}

    def self.build_index
      self.ensure_index([[:google_id, 1]], unique: true, sparse: true)
    end

    def self.lister
      self.first(:grant_type => 'lister')
    end

    def requestor
      @requestor ||= Gaps::Requestor.new(self)
    end

    def admin?
      admin
    end

    ##### Global actioning

    def username
      email.split('@')[0]
    end

    def group_member?(group)
      group_names.include?(group.group_email)
    end

    def group_member_through_list(group)
      group_names[group.group_email]
    end

    def group_member_count
      group_names.length
    end

    def group_names
      @group_names ||= transitive_closure
    end

    ### Filter things

    def set_filters(group_hash)
      filters = {}
      group_hash.each do |group_key, spec|
        filters[group_key] = {'label' => spec['label'], 'archive' => !!spec['archive']}
      end
      self.filters = filters
    end

    def all_emails
      [self.email] + self.alternate_emails
    end

    def archive?(group_id)
      spec = filters[group_id]
      if spec
        spec['archive']
      else
        true
      end
    end

    def filter_label(group_id)
      spec = filters[group_id]
      if spec
        spec['label']
      end
    end

    ### Other stuff

    def client
      client = Gaps::Requestor.base_client
      update_client(client)
      # This refreshing interface is hacky
      do_refresh(client) if refreshable

      client
    end

    def populate
      results = requestor.user_get(grant_type == 'lister' ? self.client : nil)

      self.google_id = results.fetch('id')
      self.name = results.fetch('name').fetch('fullName')
      self.email = results.fetch('primaryEmail')
      self.admin = results.fetch('isAdmin')
    end

    def self.oauth_url(lister)
      authorization_options = {access_type: :online}
      scopes = configatron.oauth.common_scopes.dup

      session_data = {
        'type' => type,
        'access_type' => authorization_options[:access_type].to_s
      }

      @google_client.authorization.scope = scopes.join(' ')
      uri = @google_client.authorization.authorization_uri(authorization_options).to_s

      [uri, session_data]
    end

    # TODO: add
    def self.persist(client, grant_type, access_type)
      requestor = Gaps::Requestor.new(nil)
      whoami = requestor.whoami(client)

      id = whoami.fetch('id')
      image_url = whoami.fetch('image').fetch('url')
      # Key will be missing if not a GAFYD user
      domain = whoami['domain']

      unless domain == configatron.info.domain
        msg = "Must authenticate as a #{configatron.info.domain} user"
        msg << ", not a #{domain} user" if domain
        raise InvalidUser.new(msg)
      end

      user = self.find_or_initialize_by_google_id(id)
      if user.new_record?
        log.info("Creating new user", user: user)
        new = true
      else
        # TODO: revoke old ones: curl https://accounts.google.com/o/oauth2/revoke?token={token}
        log.info("Clobbering access credentials", user: user)
        new = false
      end

      user.image_url = image_url

      if user.grant_type == 'lister' && grant_type != 'lister'
        log.info("Not modifying credential settings for the lister user", user: self)
      else
        user.update_credentials(client)
        user.grant_type = grant_type
        user.refreshable = access_type.to_s == 'offline'
      end

      user.populate
      user.save!

      if new && user.grant_type == 'lister'
        # When we make a new lister, we should start slurping down
        # groups.
        Gaps::DB::Group.background_refresh
        # Give it some shot of completing the refresh
        sleep(3)
      end

      user._id
    end

    def to_s
      "<User[#{_id}] google_id=#{google_id.inspect} email=#{email.inspect}>"
    end

    def update_credentials(client)
      self.refresh_token = client.authorization.refresh_token
      self.access_token = client.authorization.access_token
      self.expires_in = client.authorization.expires_in
      self.issued_at = client.authorization.issued_at
    end

    private

    def transitive_closure
      log.info('Calling transitive closure')
      subscriptions = {}
      work_queue = Queue.new

      requestor.membership_list_for_user.each do |group|
        email = group.fetch('email')
        subscriptions[email] = nil
        work_queue << email
      end

      until work_queue.empty?
        email = work_queue.pop

        # Deleted lists will return nil
        membership = requestor.membership_list_for_group(email) || []
        membership.each do |group|
          parent_email = group.fetch('email')
          next if subscriptions.include?(parent_email)
          subscriptions[parent_email] = email
          work_queue << parent_email
        end
      end

      subscriptions
    end

    def issue_time
      issued_at ? Time.at(issued_at) : nil
    end

    def update_client(client)
      client.authorization.update_token!(
        :refresh_token => refresh_token,
        :access_token => access_token,
        :expires_in => expires_in,
        :issued_at => issue_time
        )
    end

    def do_refresh(client)
      return unless client.authorization.expired?

      unless refreshable
        raise GrantExpired.new("Grant for #{self} has expired")
      end

      log.info("Refreshing expired token", user: self.to_s)
      client.authorization.fetch_access_token!

      self.update_credentials(client)
      self.save!
      update_client(client)
    end
  end
end
