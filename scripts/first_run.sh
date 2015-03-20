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

pre_start_action() {
  install_supervisor
}

post_start_action() {
    rm /first_run
}
