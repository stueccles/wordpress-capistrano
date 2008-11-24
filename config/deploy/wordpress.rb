Capistrano::Configuration.instance.load do
  default_run_options[:pty] = true
  set :deploy_to, "/var/www/apps/#{application}"
  set :scm, "git"
  set :user, "wordpress"
  set :runner, user
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

  before "deploy:setup", "puppet:initial_setup"
  before "deploy:setup", "setup:users"

  namespace :deploy do
    desc "Override deploy restart to not do anything"
    task :restart do
      #
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
  end

  namespace :setup do

    task :users do
      reset_password
      set :user, 'wordpress'
      reset_password
    end

    task :reset_password do
      user = fetch(:user, 'root')
      puts "Changing password for user #{user}"
      root_password = Capistrano::CLI.password_prompt "New UNIX password:"
      root_password_confirmation = Capistrano::CLI.password_prompt "Retype new UNIX password:"
      if root_password != ''
        if root_password == root_password_confirmation
          run "echo \"#{ root_password }\" | sudo passwd --stdin #{user}"
        else
          puts "Passwords did not match"
          exit
        end
      else
        puts "Not resetting password, none provided"
      end
    end
  end

  namespace :puppet do

    task :initial_setup do
      set :user, 'root'
      install_dependencies
      download
      update
    end

    task :install_dependencies do
      #install ruby and curl
      run "yum install -y ruby ruby-devel ruby-libs ruby-rdoc ruby-ri curl"

      #install rubygems
      run "cd /tmp && curl -OL http://rubyforge.org/frs/download.php/45905/rubygems-1.3.1.tgz"
      run "cd /tmp && tar xfz rubygems-1.3.1.tgz"
      run "cd /tmp/rubygems-1.3.1 && sudo ruby setup.rb"

      #install puppet
      run "gem install facter puppet --no-rdoc --no-ri"

      #setup puppet dir
      run "mkdir -p /var/puppet"
    end

    task :download do
      run "cd /tmp && curl -L http://github.com/jestro/puppet-wordpress/tarball/master | tar xz"
      run "rm -rf /etc/puppet"
      run "mv /tmp/jestro-puppet-wordpress* /etc/puppet"
      run "rm -rf jestro-puppet-wordpress-*"
    end

    task :update do
      run "sudo sh -c 'PATH=/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/sbin puppet /etc/puppet/manifests/site.pp'"
    end

  end

end