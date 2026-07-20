#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/keycloak/keycloak

# Read by the framework - shellcheck cannot see the caller
APP="Keycloak"
var_tags="${var_tags:-access-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  JAVA_VERSION="21" setup_java
  PG_VERSION="16" setup_postgresql
  msg_ok "Installed Dependencies"

  msg_info "Configuring PostgreSQL"
  DB_NAME="keycloak"
  DB_USER="keycloak"
  DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
  $STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  $STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8';"
  $STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
  msg_ok "Configured PostgreSQL"

  fetch_and_deploy_gh_release "keycloak_app" "keycloak/keycloak" "prebuild" "latest" "/opt/keycloak" "keycloak-*.tar.gz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/keycloak.service
[Unit]
Description=Keycloak Service
Requires=network.target
After=syslog.target network-online.target

[Service]
Type=idle
User=root
WorkingDirectory=/opt/keycloak
ExecStart=/opt/keycloak/bin/kc.sh start
ExecStop=/opt/keycloak/bin/kc.sh stop
Restart=always
RestartSec=3
Environment="JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-$(get_system_arch)"
Environment="KC_DB=postgres"
Environment="KC_DB_USERNAME=$DB_USER"
Environment="KC_DB_PASSWORD=$DB_PASS"
Environment="KC_HTTP_ENABLED=true"
Environment="KC_BOOTSTRAP_ADMIN_USERNAME=tmpadm"
Environment="KC_BOOTSTRAP_ADMIN_PASSWORD=admin123"
# Comment following line and uncomment the next 2 if working behind a reverse proxy
Environment="KC_HOSTNAME_STRICT=false"
#Environment="KC_HOSTNAME=keycloak.example.com"
#Environment="KC_PROXY_HEADERS=xforwarded"
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now keycloak
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/admin${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/keycloak ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "keycloak_app" "keycloak/keycloak"; then
    msg_info "Stopping Service"
    systemctl stop keycloak
    msg_ok "Stopped Service"

    msg_info "Updating packages"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated packages"

    msg_info "Backup old Keycloak"
    cd /opt || exit
    mv keycloak keycloak.old
    msg_ok "Backup done"

    fetch_and_deploy_gh_release "keycloak_app" "keycloak/keycloak" "prebuild" "latest" "/opt/keycloak" "keycloak-*.tar.gz"

    msg_info "Updating Keycloak"
    cd /opt || exit
    cp -a keycloak.old/conf/. keycloak/conf/
    cp -a keycloak.old/providers/. keycloak/providers/ 2> /dev/null || true
    cp -a keycloak.old/themes/. keycloak/themes/ 2> /dev/null || true
    rm -rf keycloak.old
    msg_ok "Updated Keycloak"

    msg_info "Restarting Service"
    systemctl restart keycloak
    msg_ok "Restarted Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
