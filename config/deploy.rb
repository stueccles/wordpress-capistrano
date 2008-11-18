#the domain name for the server you'll be running wordpress on
set :server, "localhost"

#the name of this wordpress project
set :application, "wordpress-capistrano-test"

#your repo
set :repository,  "git@github.com:jestro/wordpress-capistrano.git"

#the folder that your server is configured to serve wordpress from
set :deploy_to, "/Library/WebServer/Documents/wordpress"

##############################################################################
# You shouldn't need to touch the rest of this stuff.                        #
##############################################################################

default_run_options[:pty] = true
set :scm, "git"
set :deploy_via, :remote_cache
set :branch, "master"
set :git_enable_submodules, 1

#allow deploys w/o having git installed locally
set(:real_revision) { capture("git ls-remote #{repository} #{branch} | cut -f 1") }

role :app, server
role :web, server
role :db,  server, :primary => true

namespace :deploy do
  desc "Override deploy restart to not do anything"
  task :restart do
    #
  end
end