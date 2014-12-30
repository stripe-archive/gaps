#!/usr/bin/env ruby
require File.expand_path('../lib/gaps', File.dirname(__FILE__))

require 'optparse'
require 'json'
require 'rack-flash'
require 'puma'
require 'einhorn/worker'

module Gaps
  class GapsServer < Sinatra::Base
    set :server, :puma_inherit
    set :server_settings do
      {
        FD: (fd = ENV['EINHORN_FD_0']) ? fd.to_i : nil
      }
    end
    set :root, File.expand_path('../..', __FILE__)
    set :bind, '0.0.0.0'
    set :port do
      configatron.port
    end

    include Chalk::Log
    include Gaps::Third::ERBUtils::Autoescape

    use Gaps::Third::Healthcheck
    use Sinatra::CommonLogger

    ### Authentication

    before do
      if user_id = session['user_id']
        @user = Gaps::DB::User.find(user_id)

        unless @user
          log.error("Can't find user object for logged-in user_id", user_id: user_id)
          log_out!
        end
      end

      if logged_in?
        @google_client = @user.client
      else
        @google_client = Gaps::Requestor.base_client
      end
    end

    def logged_in?
      !!@user
    end

    def log_in!(user_id)
      session['user_id'] = user_id
    end

    def log_out!
      session.delete('user_id')
    end

    set(:auth) do |requirement|
      condition do
        if requirement && !logged_in?
          redirect('/login', 303)
        elsif !requirement && logged_in?
          redirect('/', 303)
        end
      end
    end

    def die(msg)
      flash.now[:error] = msg
      halt erb(:error)
    end

    get '/' do
      redirect '/subs'
    end

    get '/status', auth: false do
      if logged_in?
        status 200
        "OK"
      else
        status 401
        "UNAUTHORIZED"
      end
    end

    post '/refresh', auth: true do
      Gaps::DB::Cache.purge!
      Gaps::DB::Group.refresh
      redirect '/'
    end

    get '/login', auth: false do
      @has_lister = !!Gaps::DB::User.lister
      erb :login
    end

    post '/login_as', auth: true do
      die("Must be signed in as an admin") unless @user.admin?
      die("Must provide a username") unless username = params[:username]
      user = Gaps::DB::User.find_or_create_by_email("#{username}@#{configatron.info.domain}")
      log_in!(user._id)
      redirect '/'
    end

    get '/login/gafyd' do
      type = params[:type] || 'normal'
      authorization_options = {access_type: :online}
      scopes = configatron.oauth.common_scopes.dup

      case type
      when 'normal'
      when 'lister'
        authorization_options[:access_type] = :offline
        scopes += configatron.oauth.lister_scopes
      else
        die "Invalid login type: #{type.inspect}"
      end

      # Save this for later
      session['gafyd'] = {
        'type' => type,
        'access_type' => authorization_options[:access_type].to_s
      }

      @google_client.authorization.scope = scopes.join(' ')
      uri = @google_client.authorization.authorization_uri(authorization_options).to_s

      redirect(uri)
    end

    get '/logout', auth: true do
      flash.now[:notice] = 'Click the logout button to logout.'
      erb :notice
    end

    post '/logout', auth: true do
      log_out!
      flash.now[:notice] = 'You have been logged out.'
      erb :notice
    end

    get '/oauth2callback', auth: false do
      die "There was an error trying to complete the OAuth flow: #{params[:error]}" if params[:error]
      # In case the page was refreshed
      redirect '/login' unless params[:code]
      die "You seem to have corrupted session state. Try logging in again?" unless gafyd = session['gafyd']

      # It'd be nice to figure out what scopes I actually have, but
      # it's not clear if there's a good way to do it.
      @google_client.authorization.code = params[:code]
      begin
        @google_client.authorization.fetch_access_token!
      rescue StandardError => e
        log.error("Couldn't complete OAuth flow", e)
        die "There was an error while completing the OAuth flow: #{e}"
      end

      begin
        id = Gaps::DB::User.persist(@google_client, gafyd['type'], gafyd['access_type'])
      rescue Gaps::DB::User::InvalidUser => e
        log.error("Signed in as an invalid user", e)
        die "There was an error while completing the OAuth flow: #{e}"
      rescue Google::APIClient::ClientError => e
        if gafyd['type'] == 'lister'
          e.message << " (HINT: are you sure you're a domain admin?)"
        end
        die "There was an error completing the OAuth flow: #{e}"
        raise
      end

      log_in!(id)

      log.info("Successfully logged in", user_id: id)
      redirect('/')
    end

    ## Subscriptions

    get '/subs', auth: true do
      if !Gaps::DB::State.initialized?
        @group_count = Gaps::DB::Group.count
        @cache_count = Gaps::DB::Cache.count
        return erb(:subs_initializing)
      end

      @groups = Gaps::DB::Group.categorized(@user)
      erb :subs, :locals => {:group_partial => :_subscription_group}
    end

    post '/subs', auth: true do
      # TODO: bring back automated request logging
      log.info('Updating subscriptions', group: params[:group], user: @user.email)
      updates = 0

      params[:group].each do |group_id, group_conf|
        category = group_conf[:category].to_s
        if category.length > 0
          updates += 1
          group = Gaps::DB::Group.find(group_id)
          group.category = category
          group.save!
        end

        # TODO: refactor this
        member = !!group_conf[:member]
        was_member = group_conf[:was_member] == 'true'
        if member != was_member
          group ||= Gaps::DB::Group.find(group_id)
          if !group.viewable?(@user)
            die("Trying to update subscription to a group you do not have permission to access: #{group_id}")
          end

          if member
            @user.requestor.add_to_group(group.group_email)
          else
            @user.requestor.remove_from_group(group.group_email)
          end
        end
      end

      flash[:notice] = "Updated the category of #{updates} groups"
      redirect '/'
    end

    ## Filters

    get '/filters', auth: true do
      @groups = Gaps::DB::Group.categorized(@user, true)
      erb :filters
    end

    get '/filters/generate', auth: true do
      generic_lists = Gaps::Filter.translate_to_gmail_britta_filters(@user.filters)
      user_name = @user.email.sub(/@.*/, '')

      # Set non-xml content-type so Safari won't attempt to open the file.
      # (Yes, safari and its "Open safe files" default are awful.)
      content_type 'application/octet-stream'
      headers['Content-Disposition'] = "attachment; filename=\"#{user_name}-gmail-filters.xml\""
      Gaps::Filter.generate_filter_xml(@user.all_emails, generic_lists)
    end

    get '/filters/source', auth: true do
      content_type :text
      erb :filter_source, :layout => false
    end

    post '/filters/upload', auth: true do
      failures = Gaps::Filter.upload_to_gmail(@user)
      headers['Content-Type'] = "application/json"

      if failures.length > 0
        flash[:error] = "Failed to upload #{failures.length} filters"
      else
        flash[:notice] = "Successfully uploaded filters"
      end

      redirect '/filters'
    end

    ## AJAXy things:

    post '/ajax/groups/:group/move', auth: true do
      content_type :json
      category = params[:category]
      if group = Gaps::DB::Group.find(params[:group])
        group.move_category(category)
        {'group' => params[:group], 'category' => category}.to_json
      else
        not_found
      end
    end

    post '/ajax/users/:user/alternate_email', auth: true do
      unless user = Gaps::DB::User.find(params[:user])
        not_found
      end
      user.alternate_emails << params[:email]
      user.alternate_emails.uniq!
      user.save
      halt 201
    end

    # TODO: make this actually RESTful
    post '/ajax/users/:user/alternate_email/delete', auth: true do
      unless user = Gaps::DB::User.find(params[:user])
        not_found
      end
      user.alternate_emails.delete(params[:email])
      user.save
      halt 201
    end

    post '/ajax/filters', auth: true do
      @user.set_filters(params[:group])
      @user.save
      halt 201
    end

    helpers do
      # Insert an hidden tag with the anti-CSRF token into your forms.
      def csrf_tag
        Rack::Csrf.csrf_tag(env)
      end

      # Return the anti-CSRF token
      def csrf_token
        Rack::Csrf.csrf_token(env)
      end

      # Return the field name which will be looked for in the requests.
      def csrf_field
        Rack::Csrf.csrf_field
      end

      def default_filter(user, group)
        group.default_filter_label
      end

      def active_if_on(path)
        if request.path_info == path
          'active'
        else
          ''
        end
      end
    end
  end
end

def einhorn_main
  main
end

def main
  options = {}
  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on('-v', '--verbosity', 'Verbosity of debugging output') do
      $log.level -= 1
    end

    opts.on('-h', '--help', 'Display this message') do
      puts opts
      exit(1)
    end
  end
  optparse.parse!

  if ARGV.length != 0
    puts optparse
    return 1
  end

  Gaps.init

  Thread.new do
    # Start out just by warming the transitive closure cache, so we
    # have all of the group memberships warm and up to date.
    Gaps::DB::Group.boot

    while true
      sleep(10 * 60)

      # Every 10 minutes, go and refresh the list of all lists -- this
      # call then executes `warm_transitive_closure_cache`.
      Gaps::DB::Group.refresh_if_able
    end
  end

  Gaps::GapsServer.use(Rack::Session::Cookie, key: 'gaps',
    secret: configatron.session.secret,
    secure: configatron.session.secure,
    coder: Rack::Session::Cookie::Base64::JSON.new,
    httponly: true,
    expire_after: 12 * 30 * 7 * 24 * 60 * 60, # 1 year
    )
  Gaps::GapsServer.use(Rack::Flash)

  Einhorn::Worker.ack
  Gaps::GapsServer.run!
  return 0
end

if $0 == __FILE__
  ret = main
  begin
    exit(ret)
  rescue TypeError
    exit(0)
  end
end
