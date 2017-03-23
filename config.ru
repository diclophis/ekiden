#!/usr/bin/env ruby

require './boot'

ekiden_app = EkidenApp.new(ENV["REPO_BUCKET"], ENV["S3_ACCESS_KEY_ID"], ENV["S3_SECRET_ACCESS_KEY"])

use Rack::Auth::Basic, "Protected Area" do |username, password|
  username == 'admin' && password == 'password' #TODO: #NOTE: ensure this is changed!!!
end

map "/" do
  run(ekiden_app.index)
end

map "/packages.json" do
  run(ekiden_app.list_packages)
end

map "/delete" do
  run(ekiden_app.delete_package)
end

map "/packages" do
  run(ekiden_app.create_package)
end

map "/incoming" do
  run(ekiden_app.create_deb)
end

map "/reschedule" do
  run(ekiden_app.reschedule_work)
end

map "/resque" do
  run(Resque::Server.new)
end
