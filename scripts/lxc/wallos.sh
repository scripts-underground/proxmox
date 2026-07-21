#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ellite/wallos

# shellcheck disable=SC2034
APP="Wallos"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PHP_VERSION="8.4" PHP_APACHE="YES" setup_php
  fetch_and_deploy_gh_release "wallos" "ellite/Wallos" "tarball"

  msg_info "Installing Wallos (Patience)"
  cd /opt/wallos || exit
  mv /opt/wallos/db/wallos.empty.db /opt/wallos/db/wallos.db
  chown -R www-data:www-data /opt/wallos
  chmod -R 755 /opt/wallos
  cat << EOF > /etc/apache2/sites-available/wallos.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /opt/wallos

    <Directory /opt/wallos>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wallos_error.log
    CustomLog \${APACHE_LOG_DIR}/wallos_access.log combined
</VirtualHost>
EOF
  $STD a2ensite wallos.conf
  $STD a2dissite 000-default.conf
  $STD systemctl restart apache2
  $STD curl http://localhost/endpoints/db/migrate.php
  msg_ok "Installed Wallos"

  msg_info "Setting up Crontabs"
  $STD apt install -y cron
  mkdir -p /var/log/cron
  cat << EOF > /opt/wallos.cron
0 1 * * * php /opt/wallos/endpoints/cronjobs/updatenextpayment.php >> /var/log/cron/updatenextpayment.log 2>&1
0 2 * * * php /opt/wallos/endpoints/cronjobs/updateexchange.php >> /var/log/cron/updateexchange.log 2>&1
0 8 * * * php /opt/wallos/endpoints/cronjobs/sendcancellationnotifications.php >> /var/log/cron/sendcancellationnotifications.log 2>&1
0 9 * * * php /opt/wallos/endpoints/cronjobs/sendnotifications.php >> /var/log/cron/sendnotifications.log 2>&1
*/2 * * * * php /opt/wallos/endpoints/cronjobs/sendverificationemails.php >> /var/log/cron/sendverificationemail.log 2>&1
*/2 * * * * php /opt/wallos/endpoints/cronjobs/sendresetpasswordemails.php >> /var/log/cron/sendresetpasswordemails.log 2>&1
0 */6 * * * php /opt/wallos/endpoints/cronjobs/checkforupdates.php >> /var/log/cron/checkforupdates.log 2>&1
30 1 * * 1 php /opt/wallos/endpoints/cronjobs/storetotalyearlycost.php >> /var/log/cron/storetotalyearlycost.log 2>&1
EOF
  crontab /opt/wallos.cron
  msg_ok "Crontabs set up"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/wallos ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wallos" "ellite/Wallos"; then
    msg_info "Creating backup"
    mkdir -p /opt/logos
    mv /opt/wallos/db/wallos.db /opt/wallos.db
    mv /opt/wallos/images/uploads/logos /opt/logos/
    msg_ok "Backup created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wallos" "ellite/Wallos" "tarball"

    msg_info "Configuring Wallos"
    rm -rf /opt/wallos/db/wallos.empty.db
    mv /opt/wallos.db /opt/wallos/db/wallos.db
    mv /opt/logos/* /opt/wallos/images/uploads/logos
    if ! grep -q "storetotalyearlycost.php" /opt/wallos.cron; then
      echo "30 1 * * 1 php /opt/wallos/endpoints/cronjobs/storetotalyearlycost.php >> /var/log/cron/storetotalyearlycost.log 2>&1" >> /opt/wallos.cron
    fi
    chown -R www-data:www-data /opt/wallos
    chmod -R 755 /opt/wallos
    mkdir -p /var/log/cron
    $STD curl http://localhost/endpoints/db/migrate.php
    msg_ok "Configured Wallos"

    msg_info "Reload Apache2"
    systemctl reload apache2
    msg_ok "Apache2 Reloaded"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
