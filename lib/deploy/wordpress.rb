require 'erb'
require 'digest'
require 'digest/sha1'
Capistrano::Configuration.instance.load do
  default_run_options[:pty] = true
  set :deploy_to, "/var/www/apps/#{application}"
  set :scm, "git"
  set :user, "wordpress"
  set :admin_runner, user
  set :runner, user
  set :deploy_via, :remote_cache
  set :branch, "master"
  set :git_enable_submodules, 1
  set :puppet_tarball_url, "http://github.com/jestro/puppet-lamp/tarball/master"
  set :wordpress_db_host, "localhost"
  set :wordpress_svn_url, "http://svn.automattic.com/wordpress/tags/2.7"
  set :wordpress_auth_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_secure_auth_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_logged_in_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_nonce_key, Digest::SHA1.hexdigest(rand.to_s)

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

  #no need for log and pids directory
  set :shared_children, %w(system)

  role :app, domain
  role :web, domain
  role :db,  domain, :primary => true

  namespace :deploy do
    desc "Override deploy restart to not do anything"
    task :restart do
      #
    end

    task :finalize_update, :except => { :no_release => true } do
      run "chmod -R g+w #{latest_release}"

      run <<-CMD
        mkdir -p #{latest_release}/finalized &&
        cp -rv   #{shared_path}/wordpress/*     #{latest_release}/finalized/ &&
        cp -rv   #{shared_path}/wp-config.php   #{latest_release}/finalized/wp-config.php &&
        rm -rf   #{latest_release}/finalized/wp-content &&
        mkdir    #{latest_release}/finalized/wp-content &&
        cp -rv   #{latest_release}/themes       #{latest_release}/finalized/wp-content/ &&
        cp -rv   #{latest_release}/plugins      #{latest_release}/finalized/wp-content/
      CMD
    end

    task :symlink, :except => { :no_release => true } do
      on_rollback do
        if previous_release
          run "rm -f #{current_path}; ln -s #{previous_release}/finalized #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run "rm -f #{current_path} && ln -s #{latest_release}/finalized #{current_path}"
    end
  end

  namespace :setup do

    desc "Setup a new server for use with wordpress-capistrano. This runs as root."
    task :server do
      set :user, 'root'
      puppet.install_and_run
      util.users
      mysql.password
      util.generate_ssh_keys
    end

    desc "Setup this server for a new wordpress site."
    task :wordpress do
      sudo "mkdir -p /var/www/apps"
      sudo "chown -R wordpress /var/www/apps"
      deploy.setup
      util.passwords
      mysql.create_databases
      wp.configure
      apache.configure
      wp.checkout
    end

  end

  namespace :util do

    task :users do
      set :user, 'root'
      run "groupadd -f wheel"
      run "useradd -g wheel wordpress || echo"
      reset_password
      set :password_user, 'wordpress'
      reset_password
    end

    task :passwords do
      set :wordpress_db_name, fetch(:wordpress_db_name, Capistrano::CLI.ui.ask("New Wordpress Database Name:"))
      set :wordpress_db_user, fetch(:wordpress_db_user, Capistrano::CLI.ui.ask("New Wordpress Database User:"))
      set :wordpress_db_password, fetch(:wordpress_db_password, Capistrano::CLI.ui.ask("New Wordpress Database Password:"))
    end

    task :generate_ssh_keys do
      run "#{try_sudo} mkdir -p /home/wordpress/.ssh"
      run "#{try_sudo} chmod 700 /home/wordpress/.ssh"
      run "if [ -f /home/wordpress/.ssh/id_rsa ]; then echo 'SSH key already exists'; else #{try_sudo} ssh-keygen -q -f /home/wordpress/.ssh/id_rsa -N ''; fi"
      pubkey = capture("cat /home/wordpress/.ssh/id_rsa.pub")
      puts "Below is the SSH public key for your server."
      puts "Please add this key to your account on GitHub."
      puts ""
      puts pubkey
      puts ""
    end

    task :reset_password do
      password_user = fetch(:password_user, 'root')
      puts "Changing password for user #{password_user}"
      password_set = false
      while !password_set do
        password = Capistrano::CLI.ui.ask "New UNIX password:"
        password_confirmation = Capistrano::CLI.ui.ask "Retype new UNIX password:"
        if password != ''
          if password == password_confirmation
            run "echo \"#{ password }\" | sudo passwd --stdin #{password_user}"
            password_set = true
          else
            puts "Passwords did not match"
          end
        else
          puts "Password cannot be blank"
        end
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

  namespace :mysql do

    task :password do
      puts "Setting MySQL Password"
      password_set = false
      while !password_set do
        password = Capistrano::CLI.ui.ask "New MySQL password:"
        password_confirmation = Capistrano::CLI.ui.ask "Retype new MySQL password:"
        if password == password_confirmation
          run "mysqladmin -uroot password #{password}"
          password_set = true
        else
          puts "Passwords did not match"
        end
      end
    end

    task :create_databases do
      set :mysql_root_password, fetch(:mysql_root_password, Capistrano::CLI.password_prompt("MySQL root password:"))
      run "mysqladmin -uroot -p#{mysql_root_password} --default-character-set=utf8 create #{wordpress_db_name}"
      run "echo 'GRANT ALL PRIVILEGES ON #{wordpress_db_name}.* to \"#{wordpress_db_user}\"@\"localhost\" IDENTIFIED BY \"#{wordpress_db_password}\"; FLUSH PRIVILEGES;' | mysql -uroot -p#{mysql_root_password}"
    end

  end

  namespace :wp do

    task :checkout do
      run "rm -rf #{shared_path}/wordpress || true"
      run "svn co #{wordpress_svn_url} #{shared_path}/wordpress"
    end

    task :configure do
      file = File.join(File.dirname(__FILE__), "..", "wp-config.php.erb")
      template = File.read(file)
      buffer = ERB.new(template).result(binding)

      put buffer, "#{shared_path}/wp-config.php", :mode => 0444
    end

  end

  namespace :puppet do

    task :install_and_run do
      set :user, 'root'
      users
      install_dependencies
      download
      update
    end

    task :users do
      set :user, 'root'
      run "groupadd -f puppet"
      run "useradd -g puppet puppet || echo"
    end

    task :install_dependencies do
      set :user, 'root'
      #install ruby and curl
      run "yum install -y ruby ruby-devel ruby-libs ruby-rdoc ruby-ri curl which openssl-devel zlib-devel"

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