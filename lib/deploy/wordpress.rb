require 'erb'
Capistrano::Configuration.instance.load do
  default_run_options[:pty] = true
  set :deploy_to, "/var/www/apps/#{application}"
  set :scm, "git"
  set :user, "wordpress"
  set :runner, user
  set :deploy_via, :remote_cache
  set :branch, "master"
  set :git_enable_submodules, 1
  set :puppet_tarball_url, "http://github.com/jestro/puppet-lamp/tarball/master"

  #allow deploys w/o having git installed locally
  set(:real_revision) do
    output = ""
    invoke_command("git ls-remote #{repository} #{branch} | cut -f 1", :once => true) do |ch, stream, data|
      case stream
      when :out
        if data =~ /\(yes\/no\)\?/ # first time connecting via ssh, add to known_hosts?
          ch.send_data "yes\n"
        elsif data =~ /Warning/
        elsif data =~ /yes/
          #
        else
          output << data
        end
      when :err then warn "[err :: #{ch[:server]}] #{data}"
      end
    end
    output.gsub(/\\/, '').chomp
  end

  #no need for system, log, and pids directory
  set :shared_children, %w()

  role :app, domain
  role :web, domain
  role :db,  domain, :primary => true

  after "puppet:setup", "setup:users"
  after "deploy:setup", "apache:configure"

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
      set :user, 'root'
      run "groupadd -f wheel"
      run "useradd -g wheel wordpress || echo"
      reset_password
      set :password_user, 'root'
      reset_password
    end

    task :generate_ssh_keys do
      run "mkdir -p /home/wordpress/.ssh"
      run "chmod 700 /home/wordpress/.ssh"
      run "ssh-keygen -q -f /home/wordpress/.ssh/id_rsa -N ''"
      pubkey = capture("cat /home/wordpress/.ssh/id_rsa.pub")
      puts "Below is a freshly generated SSH public key for your server."
      puts "Please add this as a 'deploy key' to your github project."
      puts ""
      puts pubkey
      puts ""
    end

    task :reset_password do
      password_user = fetch(:password_user, 'root')
      puts "Changing password for user #{password_user}"
      root_password = Capistrano::CLI.password_prompt "New UNIX password:"
      root_password_confirmation = Capistrano::CLI.password_prompt "Retype new UNIX password:"
      if root_password != ''
        if root_password == root_password_confirmation
          run "echo \"#{ root_password }\" | sudo passwd --stdin #{password_user}"
        else
          puts "Passwords did not match"
          exit
        end
      else
        puts "Not resetting password, none provided"
      end
    end

  end

  namespace :apache do
    task :configure do
      aliases = []
      aliases << "www.#{domain}"
      aliases.concat fetch(:server_aliases, [])
      set :server_aliases_array, aliases

      file = File.join(File.dirname(__FILE__), "..", "vhost.conf.erb")
      template = File.read(file)
      buffer = ERB.new(template).result(binding)

      put buffer, "#{shared_path}/#{application}.conf", :mode => 0444
      sudo "mv #{shared_path}/#{application}.conf /etc/httpd/conf.d/"
      sudo "/etc/init.d/httpd restart"
    end
  end

  namespace :server do
    desc "Setup the server with puppet"
    task :setup do
      puppet.setup
    end
  end

  namespace :puppet do

    task :setup do
      set :user, 'root'
      users
      install_dependencies
      download
      update
    end

    task :users do
      run "groupadd -f puppet"
      run "useradd -g puppet puppet || echo"
    end

    task :install_dependencies do
      #install ruby and curl
      run "yum install -y ruby ruby-devel ruby-libs ruby-rdoc ruby-ri curl which"

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
      run "cd /tmp && mkdir puppet"
      run "cd /tmp/puppet && curl -L #{puppet_tarball_url} | tar xz"
      run "rm -rf /etc/puppet"
      run "mv /tmp/puppet/* /etc/puppet"
      run "rm -rf /tmp/puppet*"
    end

    task :update do
      run "sudo sh -c 'PATH=/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/sbin puppet /etc/puppet/manifests/site.pp'"
    end

  end

end