#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/tolgee/tolgee-platform

APP="Tolgee"
var_tags="${var_tags:-localization;i18n;developer-tools}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  JAVA_VERSION="21" setup_java
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="tolgee" PG_DB_USER="tolgee" setup_postgresql_db

  fetch_and_deploy_gh_release "tolgee" "tolgee/tolgee-platform" "singlefile" "latest" "/opt/tolgee" "tolgee-*.jar"

  msg_info "Setting up Tolgee"
  mkdir -p /opt/tolgee_data
  find /opt/tolgee -maxdepth 1 -type f -name 'tolgee-*.jar' -exec mv {} /opt/tolgee/tolgee.jar \;

  cat << EOF > /opt/tolgee_data/.env
SERVER_PORT=8080
TOLGEE_POSTGRES_AUTOSTART_ENABLED=false
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/${PG_DB_NAME}
SPRING_DATASOURCE_USERNAME=${PG_DB_USER}
SPRING_DATASOURCE_PASSWORD=${PG_DB_PASS}
TOLGEE_AUTHENTICATION_ENABLED=true
TOLGEE_AUTHENTICATION_INITIAL_USERNAME=admin
TOLGEE_FILE_STORAGE_FS_DATA_PATH=/opt/tolgee_data
EOF
  msg_ok "Set up Tolgee"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tolgee.service
[Unit]
Description=Tolgee Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tolgee
EnvironmentFile=/opt/tolgee_data/.env
ExecStart=/usr/bin/java -jar /opt/tolgee/tolgee
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tolgee
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/tolgee ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "tolgee" "tolgee/tolgee-platform"; then
    msg_info "Stopping Service"
    systemctl stop tolgee
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tolgee" "tolgee/tolgee-platform" "singlefile" "latest" "/opt/tolgee" "tolgee-*.jar"
    find /opt/tolgee -maxdepth 1 -type f -name 'tolgee-*.jar' -exec mv {} /opt/tolgee/tolgee.jar \;

    msg_info "Starting Service"
    systemctl start tolgee
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
