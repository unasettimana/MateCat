# Tested on Ubuntu 14.04
#
# checkout the project in /home/matecat/matecat
# TODO: fix directory privilges on storage / upload dirs

$project_path = '/home/matecat/matecat'

file { '/home/matecat':
	path => '/home/matecat',
	ensure => directory,
	owner => 'matecat',
	group => 'www-data'
} ->
user { 'matecat user':
	name => 'matecat',
	groups => ['www-data', 'sudo'],
	home => '/home/matecat',
	shell => '/bin/bash'
}


File { owner => 0, group => 0, mode => 0644 }

exec { "apt-update":
    command => "/usr/bin/apt-get update"
}

Exec["apt-update"] -> Package <| |> # spaceship operator https://docs.puppetlabs.com/puppet/3/reference/lang_collectors.html

# development packages
package {['zsh', 'tmux', 'git-core', 'vim']:
  ensure  => installed
}

class {'nodejs':
  version => 'v0.12.4',
} -> file {'/usr/bin/node':
  ensure => 'link',
  target => '/usr/local/node/node-default/bin/node'
} -> file {'/usr/bin/npm':
  ensure => 'link',
  target => '/usr/local/node/node-default/bin/npm'
} ->
package {'grunt-cli':
  provider => npm
} -> file {'/usr/bin/grunt':
  ensure => 'link',
  target => '/usr/local/node/node-default/bin/grunt'
}

# runtime required packages
package {['php5', 'libapache2-mod-php5', 'php5-curl', 'php5-mysql']:
  ensure  => installed
}

package {['redis-server', 'screen', 'postfix']:
  ensure => installed
}

# Apache config
apache::mod { 'rewrite': }
# apache::mod { 'filter': }
apache::mod { 'headers': }
apache::mod { 'expires': }

class { 'apache':
  mpm_module    => 'prefork',
  default_vhost => false,
  user          => 'www-data',
  group         => 'www-data'
}

class {'::apache::mod::php':
  path => "${::apache::params::lib_path}/libphp5.so",
}

apache::vhost { 'matecat':
  default_vhost => true,
  port          => 80,
  docroot       => "${project_path}",
  docroot_owner => 'matecat',
  docroot_group => 'www-data',
  priority      => 25,
  override      => ['All']
}

concat::fragment { "matecat-custom-fragment":
  target  => '25-matecat.conf',
  order   => 11,
  content => template('matecat/development-vhost.conf-fragment.erb')
}

# php configuration
file { 'php.ini':
  path    => '/etc/php5/apache2/php.ini',
  source  => 'puppet:///modules/php/php.ini',
  owner   => 'root',
  group   => 'root',
  notify  => Service["apache2"],
  require => Package['php5']
}

class { 'java':
  distribution => 'jre',
} ->
class { 'activemq': }

activemq::instance { 'matecat':
  stomp_queue_port       => 61613,
  stomp_queue            => true,
  user_name              => 'login',
  user_password          => 'passcode',
  user_auth_queue        => '>',
  authentication_enabled => false,
  authorization_enabled  => false
}

# MateCAT config
file { 'config.ini':
  path   => "${project_path}/inc/config.ini",
  source => 'puppet:///modules/matecat/config.ini',
  owner  => 'matecat',
  group  => 'www-data',
  mode   => '0755',
  replace => false
}

file { 'oauth_config.ini':
  path   => "${project_path}/inc/oauth_config.ini",
  source => 'puppet:///modules/matecat/oauth_config.ini',
  owner  => 'matecat',
  group  => 'www-data',
  mode   => '0755',
  replace => false
}

class { '::mysql::server':
  root_password           => 'strongpassword',
  remove_default_accounts => true,
  override_options        => $override_options
}

exec { 'cat lib/Model/matecat.sql lib/Model/comments.sql > /var/tmp/matecat-schema.sql':
  path    => '/bin',
  cwd     => $project_path
} ->
mysql::db { 'matecat':
  user     => 'matecat_user',
  password => 'matecat_user',
  host     => 'localhost',
  grant    => ['ALL'],
  sql      => '/var/tmp/matecat-schema.sql'
}
