#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://community.limesurvey.org/

# shellcheck disable=SC2034
APP="LimeSurvey"
var_tags="${var_tags:-survey;research;forms}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.3" PHP_APACHE="YES" PHP_FPM="YES" PHP_MODULE="imap,ldap" setup_php
  setup_mariadb

  msg_info "Configuring MariaDB Database"
  DB_NAME=limesurvey_db
  DB_USER=limesurvey
  DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD mariadb -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  $STD mariadb -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  $STD mariadb -u root -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  cat << EOF > ~/limesurvey.creds
LimeSurvey-Credentials
LimeSurvey Database User: $DB_USER
LimeSurvey Database Password: $DB_PASS
LimeSurvey Database Name: $DB_NAME
EOF
  msg_ok "Configured MariaDB Database"

  msg_info "Setting up LimeSurvey"
  temp_file=$(mktemp)
  RELEASE=$(curl -s https://community.limesurvey.org/downloads/ | grep -oE 'https://download\.limesurvey\.org/latest-master/limesurvey[0-9.+]+\.zip' | head -n1)
  curl -fsSL "$RELEASE" -o "$temp_file"
  unzip -q "$temp_file" -d /opt

  cat << EOF > /etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /opt/limesurvey
  DirectoryIndex index.php index.html index.cgi index.pl index.xhtml
  Options +ExecCGI

  <Directory /opt/limesurvey/>
    Options FollowSymLinks
    Require all granted
    AllowOverride All
  </Directory>

  <Location />
    Require all granted
  </Location>

  ErrorLog /var/log/apache2/error.log
  CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF
  chown -R www-data:www-data "/opt/limesurvey"
  chmod -R 750 "/opt/limesurvey"
  systemctl reload apache2
  rm -rf "$temp_file"
  msg_ok "Set up LimeSurvey"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/limesurvey ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  msg_warn "Application is updated via Web Interface"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
