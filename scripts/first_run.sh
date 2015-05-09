install_supervisor () {
    mkdir -p $LOG_DIR/supervisor
    mkdir -p /etc/supervisor/conf.d
    cat > /etc/supervisord.conf <<-EOF
[unix_http_server]
file=/run/supervisor.sock   ; (the path to the socket file)

[supervisord]
logfile=/var/log/supervisor/supervisord.log ; (main log file;default $CWD/supervisord.log)
logfile_maxbytes=50MB       ; (max main logfile bytes b4 rotation;default 50MB)
logfile_backups=10          ; (num of main logfile rotation backups;default 10)
loglevel=info               ; (log level;default info; others: debug,warn,trace)
pidfile=/run/supervisord.pid ; (supervisord pidfile;default supervisord.pid)
nodaemon=true               ; (start in foreground if true;default false)
minfds=1024                 ; (min. avail startup file descriptors;default 1024)
minprocs=200                ; (min. avail process descriptors;default 200)

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisor.sock ; use a unix:// URL  for a unix socket

[include]
files = /etc/supervisor/conf.d/*.conf

EOF

}

install_bugzilla() {
    mkdir -p $LOG_DIR/httpd
    chown apache:apache $LOG_DIR/httpd
    cat > /etc/httpd/conf.d/bugzilla.conf <<EOF
User apache
Group apache
ServerName $VIRTUAL_HOST:80

<VirtualHost *:80>
    AddHandler cgi-script .cgi
    ServerName localhost
    DocumentRoot "${BUGZILLA_HOME}"
    <Directory "${BUGZILLA_HOME}">
        DirectoryIndex index.cgi
        Options Indexes FollowSymLinks ExecCGI
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

EOF
  cat > /tmp/checksetup_answers.txt <<EOF
\$answer{'SMTP_SERVER'} = '$SMTP_HOST';
\$answer{'ADMIN_EMAIL'} = '$ADMIN_EMAIL';
\$answer{'ADMIN_OK'} = '$ADMIN_OK';
\$answer{'ADMIN_PASSWORD'} = '$ADMIN_PASSWORD';
\$answer{'ADMIN_REALNAME'} = '$ADMIN_REALNAME';
\$answer{'NO_PAUSE'} = 1;
\$answer{'create_htaccess'} = '';
\$answer{'cvsbin'} = '/usr/bin/cvs';
\$answer{'diffpath'} = '/usr/bin';
\$answer{'index_html'} = 0;
\$answer{'interdiffbin'} = '/usr/bin/interdiff';
\$answer{'memcached_servers'} = "localhost:11211";
\$answer{'urlbase'} = '$VIRTUAL_HOST';
\$answer{'use_suexec'} = '';
\$answer{'webservergroup'} = 'apache';
EOF

}

check_mysql() {
  DB_USER=${DB_USER:-bugs}
  DB_PASS=${DB_PASS:-CaP8VcETXUv2g}
  DB_NAME=${DB_NAME:-bugs}

  echo "mysql: $MYSQL_ENV_USER:$MYSQL_ENV_PASS@$MYSQL_PORT_3306_TCP_ADDR:$MYSQL_PORT_3306_TCP_PORT"
  RET=1
  TIMEOUT=0
  while [[ RET -ne 0 ]]; do
    echo "=> Waiting for confirmation of MariaDB service startup"
    sleep 5
    echo "Add 5 seconds to timeout"
    ((TIMEOUT+=5))
    echo "check current timeout value:$TIMEOUT"
    if [[ $TIMEOUT -gt 60 ]]; then
        echo "Failed to connect mariadb"
        exit 1
    fi
    echo "check mysql status"
    mysql -u$MYSQL_ENV_USER -p$MYSQL_ENV_PASS \
          -h$MYSQL_PORT_3306_TCP_ADDR \
          -P$MYSQL_PORT_3306_TCP_PORT \
          -e "status"
    RET=$?
    echo "mysql status is $RET"
  done

  echo "starting installation"
  if [ -z "$MYSQL_ENV_PASS" ]; then
      echo "no linked mysql detected"
  else
    echo "linked mysql detected with container id $HOSTNAME and version $MYSQL_ENV_MYSQL_VERSION"
    DB_TYPE=link_mysql
  fi

  echo 'using linked mysql'
  MYSQL_HOST=`echo $MYSQL_NAME | /bin/awk -F "/" '{print $3}'`
  echo "MySQL host is $MYSQL_HOST"
  if [ -z "$MYSQL_USER" ]; then
      echo "set MySQL user default to: $MYSQL_ENV_USER"
      MYSQL_USER=$MYSQL_ENV_USER
  fi

  echo "Creating database \"${DB_NAME}\"..."
  mysql -u$MYSQL_ENV_USER -p$MYSQL_ENV_PASS \
        -h$MYSQL_PORT_3306_TCP_ADDR \
        -P$MYSQL_PORT_3306_TCP_PORT \
        -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
  echo "Granting access to database \"${DB_NAME}\" for user \"${DB_USER}\"..."
  mysql -u$MYSQL_ENV_USER -p$MYSQL_ENV_PASS \
        -h$MYSQL_PORT_3306_TCP_ADDR \
        -P$MYSQL_PORT_3306_TCP_PORT \
        -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}' IDENTIFIED BY '${DB_PASS}';"

  cat >> /tmp/checksetup_answers.txt <<EOL
\$answer{'db_check'} = 1;
\$answer{'db_driver'} = 'mysql';
\$answer{'db_host'} = '$MYSQL_HOST';
\$answer{'db_mysql_ssl_ca_file'} = '';
\$answer{'db_mysql_ssl_ca_path'} = '';
\$answer{'db_mysql_ssl_client_cert'} = '';
\$answer{'db_mysql_ssl_client_key'} = '';
\$answer{'db_name'} = '$DB_NAME',
\$answer{'db_pass'} = '$DB_PASS';
\$answer{'db_port'} = $MYSQL_PORT_3306_TCP_PORT;
\$answer{'db_sock'} = '';
\$answer{'db_user'} = '$DB_USER';
EOL
}

install_memcached() {
  cat > /etc/supervisor/conf.d/memcached.conf <<EOF
[program:memcached]
command=/usr/bin/memcached -u memcached
stderr_logfile=/var/log/supervisor/memcached.log
stdout_logfile=/var/log/supervisor/memcached.log

EOF
}

install_httpd() {
  cat > /etc/supervisor/conf.d/httpd.conf <<EOF
[program:httpd]
command=/usr/sbin/httpd -DFOREGROUND

EOF
}
pre_start_action() {
  install_supervisor
  install_bugzilla
  check_mysql
  install_memcached
  install_httpd
  cd $BUGZILLA_HOME
  perl checksetup.pl /tmp/checksetup_answers.txt
}

post_start_action() {
    rm /first_run
}
