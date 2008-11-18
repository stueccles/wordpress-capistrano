#the domain name for the server you'll be running wordpress on
set :domain, "localhost"

#the name of this wordpress project
set :application, "wordpress-capistrano-test"

#your repo
set :repository,  "git@github.com:jestro/wordpress-capistrano.git"

#the folder wordpress will be deployed to.
#
# NOTE:
#
# Your web server will need to be configured with a DocumentRoot of 
# whatever you set below, with 'current/wordpress' added to the end.
#
# Example:
#
# set :deploy_to, "/var/www/mywordpressapp"
#
# <VirtualHost *:80>
#  ServerName foo.com
#  ServerAlias www.foo.com
#  DocumentRoot /var/www/mywordpressapp/current/wordpress
# </VirtualHost>
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
#no need for system, log, and pids directory
set :shared_children, %w()

role :app, domain
role :web, domain
role :db,  domain, :primary => true

namespace :deploy do
  desc "Override deploy restart to not do anything"
  task :restart do
    #
  end
end

task :finalize_update, :except => { :no_release => true } do
  run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
  #link the themes, plugins, and config
  run <<-CMD
    rm -rf #{latest_release}/wordpress/wp-content/themes #{latest_release}/wordpress/wp-content/plugins &&
    ln -s #{latest_release}/themes #{latest_release}/wordpress/wp-content/themes &&
    ln -s #{latest_release}/plugins #{latest_release}/wordpress/wp-content/plugins &&
    ln -s #{latest_release}/config/wp-config.php #{latest_release}/wordpress/wp-config.php
  CMD
end