#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/FreshRSS/FreshRSS

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="FreshRSS"
var_tags="${var_tags:-RSS}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="freshrss" PG_DB_USER="freshrss_usr" setup_postgresql_db

  fetch_and_deploy_gh_release "freshrss" "FreshRSS/FreshRSS" "tarball"

  msg_info "Configuring FreshRSS"
  cd /opt/freshrss || exit
  chown -R www-data:www-data /opt/freshrss
  chmod -R g+rX /opt/freshrss
  chmod -R g+w /opt/freshrss/data/
  msg_ok "Configured FreshRSS"

  msg_info "Setting up cron job for feed refresh"
  cat << EOF > /etc/cron.d/freshrss-actualize
*/15 * * * * www-data /bin/php -f /opt/freshrss/app/actualize_script.php > /tmp/FreshRSS.log 2>&1
EOF
  chmod 644 /etc/cron.d/freshrss-actualize
  msg_ok "Set up Cron - if you need to modify the timing edit file /etc/cron.d/freshrss-actualize"

  msg_info "Creating Service"
  cat << EOF > /etc/apache2/sites-available/freshrss.conf
<VirtualHost *:80>
    ServerName freshrss
    DocumentRoot /opt/freshrss/p

    <Directory /opt/freshrss/p>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/freshrss_error.log
    CustomLog /var/log/apache2/freshrss_access.log combined

    AllowEncodedSlashes On
</VirtualHost>
EOF
  $STD a2ensite freshrss
  $STD a2enmod rewrite deflate expires headers mime setenvif
  $STD a2dissite 000-default.conf
  $STD systemctl reload apache2
  msg_ok "Created Service"
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
  if [[ ! -d /opt/freshrss ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [ ! -x /opt/freshrss/cli/sensitive-log.sh ]; then
    msg_info "Fixing wrong permissions"
    chmod +x /opt/freshrss/cli/sensitive-log.sh
    systemctl restart apache2
    msg_ok "Fixed wrong permissions"
  fi

  if check_for_gh_release "freshrss" "FreshRSS/FreshRSS"; then
    msg_info "Stopping Apache2"
    systemctl stop apache2
    msg_ok "Stopped Apache2"

    msg_info "Backing up FreshRSS"
    mv /opt/freshrss /opt/freshrss-backup
    msg_ok "Backup Created"

    fetch_and_deploy_gh_release "freshrss" "FreshRSS/FreshRSS" "tarball"

    msg_info "Restoring data and configuration"
    if [[ -d /opt/freshrss-backup/data ]]; then
      cp -a /opt/freshrss-backup/data/. /opt/freshrss/data/
    fi
    if [[ -d /opt/freshrss-backup/extensions ]]; then
      cp -a /opt/freshrss-backup/extensions/. /opt/freshrss/extensions/
    fi
    msg_ok "Data Restored"

    msg_info "Setting permissions"
    chown -R www-data:www-data /opt/freshrss
    chmod -R g+rX /opt/freshrss
    chmod -R g+w /opt/freshrss/data/
    msg_ok "Permissions Set"

    msg_info "Starting Apache2"
    systemctl start apache2
    msg_ok "Started Apache2"

    msg_info "Cleaning up backup"
    rm -rf /opt/freshrss-backup
    msg_ok "Cleaned up backup"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
