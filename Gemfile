ruby '2.1.7'

# Execute bundler hook (analogous to sourcing a dotfile)
['~/.', '/etc/'].any? do |file|
 File.lstat(path = File.expand_path(file + 'bundle-gemfile-hook')) rescue next
 eval(File.read(path), binding, path); break true
end || source('https://rubygems.org/')

gem 'thread'
gem 'puma'
gem 'rack-flash3'
gem 'rack_csrf'
gem 'erubis'
gem 'sinatra'
gem 'mongo_mapper'
gem 'bson_ext'
gem 'einhorn'
gem 'chalk-log'
gem 'chalk-config'

gem 'rake'

#########
gem 'google-api-client'
gem 'configatron'
gem 'pry'
gem 'rest-client'
gem 'mail'

gem 'gmail-britta', :git => 'git://github.com/bkrausz/gmail-britta.git', :ref => 'ced6355443fe2b99f6414b2da096c70a38b23f98'

group :development, :test do
  gem 'mocha'
end
