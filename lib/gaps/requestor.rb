require 'google/api_client'

module Gaps
  class Requestor
    include Chalk::Log

    attr_accessor :user

    def initialize(user)
      @user = user
    end

    def self.base_client
      client = Google::APIClient.new(
        application_name: 'Gaps',
        application_version: '1.0'
        )
      client.authorization.client_id = configatron.oauth.client_id
      client.authorization.client_secret = configatron.oauth.client_secret
      client.authorization.redirect_uri = configatron.oauth.redirect_uri
      client
    end

    def whoami(client=nil)
      client ||= :user

      # API call: https://developers.google.com/+/api/latest/people/get
      request(client, 'Figuring out who this OAuth token belongs to',
        uri: 'https://www.googleapis.com/plus/v1/people/me')
    end

    def user_get(client=nil)
      client ||= :lister
      # API call: https://developers.google.com/admin-sdk/directory/v1/reference/users/get
      request(client, 'Requesting user info',
        uri: uri('https://www.googleapis.com/admin/directory/v1/users', user.google_id)
        )
    end

    def group_list
      # https://developers.google.com/admin-sdk/directory/v1/reference/groups/list
      responses = request_all(:user, 'Requesting all groups',
        {uri: 'https://www.googleapis.com/admin/directory/v1/groups'},
        domain: configatron.info.domain,
        )
      responses.map {|response| response.fetch('groups')}.flatten(1)
    end

    ##### Per-account actioning

    # We cache group results in memory and in the database, since
    # we'll make many of these queries. Since the end user may not
    # have permission to view all the groups, we need to use the
    # lister client. We use this information to tell the user which
    # lists they are indirectly subscribed to.
    def membership_list_for_group(email)
      Gaps::DB::Cache.with_cache_key("mygroupinfos:#{email}") do
        membership_list(email)
      end
    end

    def membership_list_for_user
      membership_list(user.email)
    end

    def membership_list(email)
      # https://developers.google.com/admin-sdk/directory/v1/reference/groups/list
      responses = request_all(:lister, 'Finding all groups containing email',
        {uri: 'https://www.googleapis.com/admin/directory/v1/groups'},
        domain: configatron.info.domain,
        userKey: email
        )
      responses.
        map {|response| response['groups']}.
        flatten(1).
        # Groups entry may be nil if you don't have perms to list the
        # group (such as groups off your domain).
        compact.
        # Only include groups from your domain.
        select {|group| group.fetch('email').ends_with?('@' + configatron.info.domain)}
    end

    def add_to_group(group_email)
      request(:lister, "Adding #{user.email} to group",
        uri: uri('https://www.googleapis.com/admin/directory/v1/groups', group_email, 'members'),
        http_method: 'post',
        headers: {'Content-Type' => 'application/json'},
        body: JSON.generate(
          email: user.email,
          role: 'MEMBER'
          )
        )
    end

    def update_group_description(group_email, group_description)
      request(:lister, "Updating #{group_email}'s description",
        uri: uri('https://www.googleapis.com/groups/v1/groups', group_email),
        http_method: 'put',
        headers: {'Content-Type' => 'application/json'},
        body: JSON.generate(
          description: group_description
          )
        )
    end

    def remove_from_group(group_email)
      request(:lister, "Removing user from group",
        uri: uri('https://www.googleapis.com/admin/directory/v1/groups', group_email, 'members', user.email),
        http_method: 'delete'
        )
    end

    def create_filter(properties)
      user_name = user.email.split('@')[0]

      body = '<?xml version="1.0" encoding="utf-8"?>' + "\n"
      body += '<atom:entry xmlns:atom="http://www.w3.org/2005/Atom" xmlns:apps="http://schemas.google.com/apps/2006">' + "\n"
      body += properties + "\n" # Hacky hack hack
      body += '</atom:entry>'

      request(:lister, "Adding filter: #{properties.inspect} for #{user.email}",
        uri: uri('https://apps-apis.google.com/a/feeds/emailsettings/2.0', configatron.info.domain, user_name, 'filter'),
        http_method: 'post',
        headers: {'Content-Type' => 'application/atom+xml'},
        body: body
        )
    end

    def get_group_settings(group_email)
      request(:lister, "Retrieving settings for group",
        uri: uri('https://www.googleapis.com/groups/v1/groups', group_email)
        )
    end

    def get_group(group_email)
      request(:lister, "Retrieving group object",
        uri: uri('https://www.googleapis.com/admin/directory/v1/groups', group_email)
        )
    end

    private

    def uri(*args)
      Gaps::Third::URIUtils.build(*args)
    end

    def lister_client
      Gaps::DB::User.lister.client
    end

    def user_client
      @user.client
    end

    def get_client(client_spec)
      case client_spec
      when :lister
        client = lister_client()
      when :user
        client = user_client()
      when Google::APIClient
        client = client_spec
      else
        raise "Unrecognized client type: #{client_spec.inspect}"
      end
    end

    def request(client_spec, text, opts)
      uri = opts.fetch(:uri)
      log.info(text, uri: uri)

      client = get_client(client_spec)

      rate_limit = 0
      invalid_credentials = false
      begin
        response = client.execute!(
          opts.merge(parameters: {alt: 'json'})
          )
      rescue Google::APIClient::ClientError => e
        if e.message =~ /\AInvalid Credentials/ && !invalid_credentials
          # Give ourselves a chance to refresh the client credentials
          invalid_credentials = true
          client = get_client(client_spec)
          retry
        elsif e.message =~ /\ARequest rate higher than configured/ && rate_limit < 5
          # If we just exceeded the rate limit, cool off
          rate_limit += 1
          sleeping = 2**rate_limit + 3 * rand
          log.info('Just hit rate limit', rate_limit: rate_limit, sleep: sleeping)
          sleep(sleeping)
          retry
        else
          raise
        end
      end

      response.data
    end

    def request_all(client_spec, text, opts, query_params)
      responses = []

      base_uri = opts[:uri]
      page_token = nil
      (0..Float::INFINITY).each do |page|
        query_params[:pageToken] = page_token
        opts[:uri] = uri(base_uri, query_params)

        response = request(client_spec, text + " (page: #{page})", opts)
        responses << response

        unless page_token = response['nextPageToken']
          break
        end
      end

      responses
    end
  end
end
