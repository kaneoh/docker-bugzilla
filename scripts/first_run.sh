install_smtp() {
  touch /etc/msmtprc
  mkdir -p $LOG_DIR/msmtp
  chown nginx:nginx $LOG_DIR/msmtp
  cat > /etc/msmtprc <<EOF
# The SMTP server of the provider.
defaults
logfile $LOG_DIR/msmtp/msmtplog

account mail
host $SMTP_HOST
port $SMTP_PORT
user $SMTP_USER
password $SMTP_PASS
auth login
tls on
tls_trust_file /etc/pki/tls/certs/ca-bundle.crt

account default : mail

EOF
  chmod 600 /etc/msmtprc
}

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
  mkdir -p $LOG_DIR/nginx
  mkdir -p $LOG_DIR/bugzilla
  cat > /etc/supervisor/conf.d/bugzilla.conf <<EOF
[program:fastcgi_wrapper]
process_name=%(program_name)s_%(process_num)02d
numprocs=1
;socket=tcp://127.0.0.1:8999
;socket=unix:///var/run/fastcgi-wrapper/fastcgi-wrapper.sock
;socket_mode=0777
command=/scripts/fastcgi-wrapper.pl
user=nginx
group=nginx
stdout_logfile=/var/log/bugzilla/fastcgi_wrapper.log
stderr_logfile=/var/log/bugzilla/fastcgi_wrapper.err
redirect_stderr=true
priority=1000
autostart=true
autorestart=true

[program:nginx]
priority=100
command=/usr/sbin/nginx

EOF

cat > /etc/nginx/sites-enabled/default <<EOF
server {
  listen        80;
  server_name   $VIRTUAL_HOST;

  access_log /var/log/bugzilla/access.log;
  error_log  /var/log/bugzilla/error.log;

  root       /home/bugzilla/www;
  index      index.cgi index.txt index.html index.xhtml;

  location / {
    autoindex off;
  }

  location ~ ^.*\.cgi$ {
    try_files \$uri =404;
    gzip off;

    # fastcgi_pass  unix:/var/run/fastcgi-wrapper/fastcgi-wrapper.sock;
    fastcgi_pass  127.0.0.1:8999;
    fastcgi_index index.cgi;

    fastcgi_param  QUERY_STRING       \$query_string;
    fastcgi_param  REQUEST_METHOD     \$request_method;
    fastcgi_param  CONTENT_TYPE       \$content_type;
    fastcgi_param  CONTENT_LENGTH     \$content_length;

    fastcgi_param  SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
    fastcgi_param  SCRIPT_NAME        \$fastcgi_script_name;
    fastcgi_param  REQUEST_URI        \$request_uri;
    fastcgi_param  DOCUMENT_URI       \$document_uri;
    fastcgi_param  DOCUMENT_ROOT      \$document_root;
    fastcgi_param  SERVER_PROTOCOL    \$server_protocol;

    fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
    fastcgi_param  SERVER_SOFTWARE    nginx/\$nginx_version;

    fastcgi_param  REMOTE_ADDR        \$remote_addr;
    fastcgi_param  REMOTE_PORT        \$remote_port;
    fastcgi_param  SERVER_ADDR        \$server_addr;
    fastcgi_param  SERVER_PORT        \$server_port;
    fastcgi_param  SERVER_NAME        \$server_name;
  }
}
EOF
cat > /home/bugzilla/localconfig <<EOF
\$create_htaccess = 1;
\$webservergroup = 'nginx';
\$use_suexec = 0;
\$index_html = 0;
\$interdiffbin = '';
\$diffpath = '/usr/bin';
\$site_wide_secret = 'KDKOJKYNhrURHOjdgRK7ORlLleXmJO6gRP5U2LCB59kMRIQK9sBfs7a3huyTZxnh';
EOF
}

check_mysql() {
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
      cat >> /home/bugzilla/localconfig <<EOL
\$db_driver = 'mysql';
\$db_host = '$MYSQL_HOST';
\$db_name = 'bugs';
\$db_user = '$MYSQL_USER';
\$db_pass = '$MYSQL_ENV_PASS';
\$db_port = '$MYSQL_ENV';
\$db_sock = '$MYSQL_PORT_3306_TCP_PORT';
\$db_check = 1;
\$db_mysql_ssl_ca_file = '';
\$db_mysql_ssl_ca_path = '';
\$db_mysql_ssl_client_cert = '';
\$db_mysql_ssl_client_key = '';
EOL

}

pre_start_action() {
  install_supervisor
  install_bugzilla
  check_mysql
}

post_start_action() {
    rm /first_run
}
