#!/usr/bin/env rake

desc 'Build gaps-srv'
task :build do
end

namespace :deploy do
  desc 'Deploy gaps-srv'
  task 'gaps-srv' do
    sh 'ln', '-s', '/etc/gaps-srv-site.yaml', 'site.yaml'
    sh 'svc', '-h', '/etc/service/gaps-srv'
  end
end
