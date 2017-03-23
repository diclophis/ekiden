require 'rubygems'
require 'resque'
require 'fog'
require 'markaby'
require 'aws-sdk'
require 'tempfile'
require 'yaml'
require 'tempfile'
require 'rack'
require 'resque/server'
require 'tilt/erb'

require './marvin'
require "./ekiden_app"
require './ekiden_deb_s3_worker'
require './ekiden_fpm_worker'

unless ENV['REPO_BUCKET'] && ENV['S3_ACCESS_KEY_ID'] && ENV['S3_SECRET_ACCESS_KEY']
  local_secret_path = File.join(ENV["HOME"], ".package-repo-s3.yml")
  tokens = YAML.load(File.read(local_secret_path))

  raise unless ENV['REPO_BUCKET']

  ENV['S3_ACCESS_KEY_ID'] = tokens['apt-rw-access-key']
  ENV['S3_SECRET_ACCESS_KEY'] = tokens['apt-rw-secret-key']
  ENV['AWS_ACCESS_KEY_ID'] = ENV['AWS_ACCESS_KEY_ID'] || ENV['S3_ACCESS_KEY_ID']
  ENV['AWS_SECRET_ACCESS_KEY'] = ENV['AWS_SECRET_ACCESS_KEY'] || ENV['S3_SECRET_ACCESS_KEY']
end
