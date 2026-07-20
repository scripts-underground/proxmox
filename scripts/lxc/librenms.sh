#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.librenms.org/ | Github: https://github.com/librenms/librenms

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LibreNMS"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    acl \
    fping \
    graphviz \
    imagemagick \
    mtr-tiny \
    nginx \
    nmap \
    rrdtool \
    snmp \
    snmpd \
    whois
  msg_ok "Installed Dependencies"

  msg_info "Installing Python Dependencies"
  $STD apt install -y \
    python3-dotenv \
    python3-pymysql \
    python3-redis \
    python3-setuptools \
    python3-systemd \
    python3-pip \
    python3-psutil \
    python3-command-runner
  msg_ok "Installed Python Dependencies"

  PHP_VERSION="8.4" PHP_FPM="YES" PHP_MODULE="cli,snmp,gmp" setup_php
  setup_mariadb
  setup_composer
  PYTHON_VERSION="3.13" setup_uv
  MARIADB_DB_NAME="librenms" MARIADB_DB_USER="librenms" MARIADB_DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)" setup_mariadb_db
  fetch_and_deploy_gh_release "librenms" "librenms/librenms" "tarball"

  msg_info "Configuring LibreNMS"
  $STD useradd librenms -d /opt/librenms -M -r -s "$(which bash)"
  mkdir -p /opt/librenms/{rrd,logs,bootstrap/cache,storage,html}
  cd /opt/librenms || exit
  APP_KEY=$(openssl rand -base64 40 | tr -dc 'a-zA-Z0-9')
  $STD uv venv --clear .venv
  $STD source .venv/bin/activate
  $STD uv pip install -r requirements.txt
  cat << EOF > /opt/librenms/.env
DB_DATABASE=${MARIADB_DB_NAME}
DB_USERNAME=${MARIADB_DB_USER}
DB_PASSWORD=${MARIADB_DB_PASS}
APP_KEY=${APP_KEY}
EOF
  chown -R librenms:librenms /opt/librenms
  chmod 771 /opt/librenms
  chmod -R ug=rwX /opt/librenms/bootstrap/cache /opt/librenms/storage /opt/librenms/logs /opt/librenms/rrd
  msg_ok "Configured LibreNMS"

  msg_info "Configure MariaDB"
  sed -i "/\[mariadb\]/a innodb_file_per_table=1\nlower_case_table_names=0" /etc/mysql/mariadb.conf.d/50-server.cnf
  systemctl enable -q --now mariadb
  msg_ok "Configured MariaDB"

  msg_info "Configure PHP-FPM"
  cp /etc/php/8.4/fpm/pool.d/www.conf /etc/php/8.4/fpm/pool.d/librenms.conf
  sed -i "s/\[www\]/\[librenms\]/g" /etc/php/8.4/fpm/pool.d/librenms.conf
  sed -i "s/user = www-data/user = librenms/g" /etc/php/8.4/fpm/pool.d/librenms.conf
  sed -i "s/group = www-data/group = librenms/g" /etc/php/8.4/fpm/pool.d/librenms.conf
  sed -i "s/listen = \/run\/php\/php8.4-fpm.sock/listen = \/run\/php-fpm-librenms.sock/g" /etc/php/8.4/fpm/pool.d/librenms.conf
  msg_ok "Configured PHP-FPM"

  msg_info "Configure Nginx"
  cat << EOF > /etc/nginx/sites-enabled/librenms
server {
 listen      80;
 server_name ${LOCAL_IP};
 root        /opt/librenms/html;
 index       index.php;

 charset utf-8;
 gzip on;
 gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
 location / {
  try_files \$uri \$uri/ /index.php?\$query_string;
 }
 location ~ [^/]\.php(/|$) {
  fastcgi_pass unix:/run/php-fpm-librenms.sock;
  fastcgi_split_path_info ^(.+\.php)(/.+)$;
  include fastcgi.conf;
 }
 location ~ /\.(?!well-known).* {
  deny all;
 }
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  systemctl restart php8.4-fpm
  msg_ok "Configured Nginx"

  msg_info "Configure Services"
  ln -sf /opt/librenms/lnms /usr/bin/lnms
  mkdir -p /etc/bash_completion.d/
  cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/
  cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf

  APP_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  APP_USER="admin"
  cat << EOF > ~/librenms.creds
LibreNMS Credentials
Username: ${APP_USER}
Password: ${APP_PASSWORD}
EOF

  $STD su - librenms -s /bin/bash -c "cd /opt/librenms && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev"
  $STD su - librenms -s /bin/bash -c "cd /opt/librenms && php8.4 artisan migrate --force"
  $STD su - librenms -s /bin/bash -c "cd /opt/librenms && php8.4 artisan key:generate --force"
  $STD su - librenms -s /bin/bash -c "cd /opt/librenms && lnms db:seed --force"
  $STD su - librenms -s /bin/bash -c "cd /opt/librenms && lnms user:add -p ${APP_PASSWORD} ${APP_USER} --role=admin"

  RANDOM_STRING=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')
  sed -i "s/RANDOMSTRINGHERE/$RANDOM_STRING/g" /etc/snmp/snmpd.conf
  echo "SNMP Community String: $RANDOM_STRING" >> ~/librenms.creds
  curl -sqo /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
  chmod +x /usr/bin/distro
  systemctl enable -q --now snmpd

  cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms
  cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/

  systemctl enable -q --now librenms-scheduler.timer
  cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
  msg_ok "Configured Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Admin credentials saved to ~/librenms.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/librenms ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "librenms" "librenms/librenms"; then
    msg_info "Stopping Services"
    systemctl stop php8.4-fpm librenms-scheduler.timer
    msg_ok "Stopped Services"

    create_backup /opt/librenms/.env /opt/librenms/config.php /opt/librenms/rrd
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "librenms" "librenms/librenms" "tarball"
    restore_backup

    msg_info "Updating LibreNMS"
    mkdir -p /opt/librenms/{rrd,logs,bootstrap/cache,storage}
    chown -R librenms:librenms /opt/librenms
    chmod 771 /opt/librenms
    chmod -R ug=rwX /opt/librenms/bootstrap/cache /opt/librenms/storage /opt/librenms/logs /opt/librenms/rrd
    $STD su - librenms -s /bin/bash -c "cd /opt/librenms && uv venv --clear .venv && source .venv/bin/activate && uv pip install -r requirements.txt"
    $STD su - librenms -s /bin/bash -c "cd /opt/librenms && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev"
    $STD su - librenms -s /bin/bash -c "cd /opt/librenms && php8.4 artisan optimize:clear"
    $STD su - librenms -s /bin/bash -c "cd /opt/librenms && php8.4 artisan migrate --force --isolated"
    msg_ok "Updated LibreNMS"

    msg_info "Starting Services"
    systemctl start php8.4-fpm librenms-scheduler.timer
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
