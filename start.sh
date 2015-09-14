#!/bin/bash

# Disable Strict Host checking for non interactive git clones
mkdir -p -m 0700 /root/.ssh
cp -rf /opt/ngddeploy/$VIRTUAL_HOST/* /root/.ssh/ 
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config


# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
 git config --global user.email "$GIT_EMAIL"
fi
if [ ! -z "$GIT_NAME" ]; then
 git config --global user.name "$GIT_NAME"
 git config --global push.default simple
fi

# Pull down code form git for our site!
if [ ! -z "$GIT_REPO" ]; then
  rm -rf /usr/share/nginx/html/*
  rm -rf /usr/share/nginx/html/.* 2> /dev/null
  if [ ! -z "$GIT_BRANCH" ]; then
    git clone -b $GIT_BRANCH $GIT_REPO /usr/share/nginx/html/
    chown -Rf www-data:www-data /usr/share/nginx/*
  else
    git clone $GIT_REPO /usr/share/nginx/html/
    chown -Rf www-data:www-data /usr/share/nginx/*
  fi
  chown -Rf nginx.nginx /usr/share/nginx/*
fi

# Pull down database dump form git for our site!
if [ ! -z "$GIT_DB_REPO" ]; then
  mkdir -p /usr/share/mysql/dumps && rm -rf /usr/share/mysql/dumps/*
  rm -rf /usr/share/mysql/dumps/.* 2> /dev/null
  if [ ! -z "$GIT_DB_BRANCH" ]; then
    git clone -b $GIT_DB_BRANCH $GIT_DB_REPO /usr/share/mysql/dumps/
    chown -Rf mysql:mysql /usr/share/mysql/dumps/*
  else
    git clone $GIT_DB_REPO /usr/share/mysql/dumps/
    chown -Rf mysql:mysql /usr/share/mysql/dumps/*
  fi
  chown -Rf mysql:mysql /usr/share/mysql/dumps/*
  /usr/bin/mysqld_safe & sleep 10s
  # Here we generate random passwords (thank you pwgen!). The first two are for mysql users, the last batch for random keys in wp-config.php
  MYSQL_PASSWORD=`pwgen -c -n -1 12`
  mysqladmin -u root password $MYSQL_PASSWORD
  mysql -uroot -p$MYSQL_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  mysql -uroot -p$MYSQL_PASSWORD -e "CREATE DATABASE $WORDPRESS_DB; GRANT ALL PRIVILEGES ON $WORDPRESS_DB.* TO '$WORDPRESS_DB_USER'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD'; FLUSH PRIVILEGES;"
  mysql -uroot -p$MYSQL_PASSWORD $WORDPRESS_DB < /usr/share/mysql/dumps/*.sql
  killall mysqld
fi

if [ ! -f /usr/share/nginx/www/wp-config.php ]; then
  #mysql has to be started this way as it doesn't work to call from /etc/init.d
  /usr/bin/mysqld_safe &
  sleep 10s
  # Here we generate random passwords (thank you pwgen!). The first two are for mysql users, the last batch for random keys in wp-config.php
  WORDPRESS_DB="wordpress"
  MYSQL_PASSWORD=`pwgen -c -n -1 12`
  WORDPRESS_PASSWORD=`pwgen -c -n -1 12`
  #This is so the passwords show up in logs.
  echo mysql root password: $MYSQL_PASSWORD
  echo wordpress password: $WORDPRESS_PASSWORD
  echo $MYSQL_PASSWORD > /mysql-root-pw.txt
  echo $WORDPRESS_PASSWORD > /wordpress-db-pw.txt

  sed -e "s/database_name_here/$WORDPRESS_DB/
  s/username_here/$WORDPRESS_DB/
  s/password_here/$WORDPRESS_PASSWORD/
  /'AUTH_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'SECURE_AUTH_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'LOGGED_IN_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'NONCE_KEY'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'AUTH_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'SECURE_AUTH_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'LOGGED_IN_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/
  /'NONCE_SALT'/s/put your unique phrase here/`pwgen -c -n -1 65`/" /usr/share/nginx/www/wp-config-sample.php > /usr/share/nginx/www/wp-config.php

  # Download nginx helper plugin
  curl -O `curl -i -s https://wordpress.org/plugins/nginx-helper/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+"`
  unzip -o nginx-helper.*.zip -d /usr/share/nginx/www/wp-content/plugins
  chown -R www-data:www-data /usr/share/nginx/www/wp-content/plugins/nginx-helper

  # Activate nginx plugin once logged in
  cat << ENDL >> /usr/share/nginx/www/wp-config.php
\$plugins = get_option( 'active_plugins' );
if ( count( \$plugins ) === 0 ) {
  require_once(ABSPATH .'/wp-admin/includes/plugin.php');
  \$pluginsToActivate = array( 'nginx-helper/nginx-helper.php' );
  foreach ( \$pluginsToActivate as \$plugin ) {
    if ( !in_array( \$plugin, \$plugins ) ) {
      activate_plugin( '/usr/share/nginx/www/wp-content/plugins/' . \$plugin );
    }
  }
}
ENDL

  chown www-data:www-data /usr/share/nginx/www/wp-config.php

  mysqladmin -u root password $MYSQL_PASSWORD
  mysql -uroot -p$MYSQL_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  mysql -uroot -p$MYSQL_PASSWORD -e "CREATE DATABASE wordpress; GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD'; FLUSH PRIVILEGES;"
  killall mysqld
fi

# start all the services
/usr/local/bin/supervisord -n
