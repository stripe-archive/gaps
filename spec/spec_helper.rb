require 'rack/test'
require 'rspec'
require 'pry-byebug'

require File.expand_path '../../bin/gaps_server.rb', __FILE__

ENV['RACK_ENV'] = 'test'

module RSpecMixin
  include Rack::Test::Methods
  def app() Gaps end
end

RSpec.configure { |c| c.include RSpecMixin }
