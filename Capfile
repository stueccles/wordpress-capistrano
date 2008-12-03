load 'deploy'

#the domain name for the server you'll be running wordpress on
set :domain, "localhost"

#other domain names your app will respond to (dev.blog.com, etc)
#set :server_aliases, []

#the name of this wordpress project
set :application, "wordpress-capistrano-test"

#your repo
set :repository,  "git@github.com:jestro/wordpress-capistrano.git"

#if you've forked and customized puppet-lamp, enter the url to your repos tarball here
#set :puppet_tarball_url, "http://github.com/jestro/puppet-lamp/tarball/master"

require File.join(File.dirname(__FILE__), 'lib', 'deploy', 'wordpress')