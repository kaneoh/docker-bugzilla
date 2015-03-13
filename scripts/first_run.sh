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
}

install_nginx() {
  rm -f /etc/nginx/sites-enabled/no-default
  cat > /etc/nginx/sites-enabled/default.conf <<EOF
# default server
#
server {
    listen       80 default_server;
    server_name  $VIRTUAL_HOST;

    root /usr/share/nginx/owncloud;

    client_max_body_size 10G; # set max upload size
    fastcgi_buffers 64 4K;

    rewrite ^/caldav(.*)\$ /remote.php/caldav\$1 redirect;
    rewrite ^/carddav(.*)\$ /remote.php/carddav\$1 redirect;
    rewrite ^/webdav(.*)\$ /remote.php/webdav\$1 redirect;

    index index.php;

    location = /robots.txt {
       allow all;
       log_not_found off;
       access_log off;
    }

    location / {
        root   /usr/share/nginx/owncloud;
        index  index.php;
        # The following 2 rules are only needed with webfinger
        rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
        rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
        rewrite ^/.well-known/carddav /remote.php/carddav/ redirect;
        rewrite ^/.well-known/caldav /remote.php/caldav/ redirect;
        rewrite ^(/core/doc/[^\/]+/)\$ \$1/index.html;
        try_files \$uri \$uri/ index.php;
    }

    location ~ \.php(?:\$|/) {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include conf/fastcgi_params.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~* ^.+\.(jpg|jpeg|gif|bmp|ico|png|css|js|swf)\$ {
        expires 30d;
        access_log off;
    }

    location ~ ^/(data|config|\.ht|db_structure\.xml|README) {
        deny all;
    }
}

EOF


  #
  if [ -z "$SSL_SELFSIGNED" ]; then
      echo "no SSL"
  else
    echo "generating selfsigned cert"
    if [ -z "$SSL_PROTOCOLS" ]; then
        echo "set default SSL protocol"
        SSL_PROTOCOLS=$SSL_PROTOCOLS_DEFAULT
    fi
    if [ -z "$SSL_CIPHERS" ]; then
        echo "set default SSL ciphers"
        SSL_CIPHERS=$SSL_CIPHERS_DEFAULT
    fi

    mkdir -p /etc/nginx/ssl/
    chown nginx:nginx /etc/nginx/ssl/

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt <<SSL
CN
Shanghai
Shanghai
Wekin inc.
Sys
$VIRTUAL_HOST
li.zhiguang@moretv.com.cn
SSL

    cat > /etc/nginx/sites-enabled/ssl.conf <<EOF
# default server
#
server {
    listen       443 ssl;
    server_name          $VIRTUAL_HOST;
    ssl                  on;
    ssl_certificate      /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key  /etc/nginx/ssl/nginx.key;
    ssl_session_timeout  5m;
    ssl_protocols        $SSL_PROTOCOLS;
    ssl_ciphers          $SSL_CIPHERS;
    ssl_prefer_server_ciphers   on;

    root /usr/share/nginx/owncloud;

    client_max_body_size 10G; # set max upload size
    fastcgi_buffers 64 4K;

    rewrite ^/caldav(.*)\$ /remote.php/caldav\$1 redirect;
    rewrite ^/carddav(.*)\$ /remote.php/carddav\$1 redirect;
    rewrite ^/webdav(.*)\$ /remote.php/webdav\$1 redirect;

    index index.php;

    location = /robots.txt {
       allow all;
       log_not_found off;
       access_log off;
    }

    location / {
        root   /usr/share/nginx/owncloud;
        index  index.php;
        # The following 2 rules are only needed with webfinger
        rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
        rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
        rewrite ^/.well-known/carddav /remote.php/carddav/ redirect;
        rewrite ^/.well-known/caldav /remote.php/caldav/ redirect;
        rewrite ^(/core/doc/[^\/]+/)\$ \$1/index.html;
        try_files \$uri \$uri/ index.php;
    }

    location ~ \.php(?:\$|/) {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include conf/fastcgi_params.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
    }

    location ~* ^.+\.(jpg|jpeg|gif|bmp|ico|png|css|js|swf)\$ {
        expires 30d;
        access_log off;
    }

    location ~ ^/(data|config|\.ht|db_structure\.xml|README) {
        deny all;
    }
}

EOF
  fi

  cat > /etc/php-fpm.conf <<EOF
[global]
pid = /run/php-fpm/php-fpm.pid
error_log = /var/log/php-fpm/error.log
daemonize = no
[www]
user = nginx
group = nginx
listen = /var/run/php-fpm/www.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0666
pm = dynamic
pm.max_children = 4
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
catch_workers_output = yes
php_admin_value[error_log] = /var/log/php-fpm/owncloud.php.log
php_admin_value[sendmail_path] = /usr/bin/msmtp -t -C /etc/msmtprc

EOF
  cd $DATA_DIR

  # Set up the nginx code base
  chown nginx:nginx $DATA_DIR
}

pre_start_action() {
}

post_start_action() {
    rm /first_run
}
