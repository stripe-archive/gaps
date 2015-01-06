#!/usr/bin/env rake
require 'rake/testtask'

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

Rake::TestTask.new do |t|
  t.libs = ["lib"]
  # t.warning = true
  t.verbose = true
  t.test_files = FileList['test/**/*.rb'].reject do |file|
    file.end_with?('_lib.rb') || file.include?('/_lib/')
  end
end
