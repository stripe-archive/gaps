require 'rubygems'
require 'bundler/setup'
require 'gmail-britta'
require 'sinatra'
require 'rack/csrf'
require 'chalk-log'
require 'chalk-config'
require 'thread/channel'
require 'thread/future'
require 'thread/pool'
require 'thread/promise'

module Gaps
  include Chalk::Log

  def self.init
    Thread.abort_on_exception = true

    Gaps::Third::YAMLUtils.make_yaml_safe!
    Gaps::Third::JSONUtils.make_json_safe!

    Chalk::Config.environment = (ENV['RACK_ENV'] || 'development')

    Chalk::Config.register(File.expand_path('../../config.yaml', __FILE__))

    begin
      Chalk::Config.register(File.expand_path('../../site.yaml', __FILE__), raw: true)
    rescue Errno::ENOENT => e
      $stderr.puts "ERROR: It looks like you have no `site.yaml` file. Please copy the `site.yaml.sample` to `site.yaml` and populate the fields, per https://github.com/stripe/gaps#configuring"
      exit(1)
    end

    Gaps::DB.init
    Gaps::DB::Cache.start_cache_lookup
  end
end

require_relative 'gaps/db'
require_relative 'gaps/filter'
require_relative 'gaps/email'
require_relative 'gaps/requestor'
require_relative 'gaps/third'

if $0 == 'irb' || $0 == 'pry'
  Gaps.init
end
