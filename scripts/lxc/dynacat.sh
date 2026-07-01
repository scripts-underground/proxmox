#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Panonim/dynacat


# Read by the framework - shellcheck cannot see the caller\n# shellcheck disable=SC2034\nAPP="Dynacat"
var_tags="${var_tags:-dashboard;homepage;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "dynacat" "Panonim/dynacat" "prebuild" "latest" "/opt/dynacat" "dynacat-linux-amd64.tar.gz"

  msg_info "Setting up Dynacat"
  mkdir -p /opt/dynacat/config /opt/dynacat/assets /opt/dynacat/data
  chmod +x /opt/dynacat/dynacat

  cat << EOF > /opt/dynacat/config/dynacat.yml
server:
  host: 0.0.0.0
  port: 8080
  assets-path: /opt/dynacat/assets
  db-path: /opt/dynacat/data/dynacat.db

pages:
  - name: Home
    columns:
      - size: small
        widgets:
          - type: calendar
          - type: clock
      - size: full
        widgets:
          - type: search
            search-engine: duckduckgo
          - type: monitor
            title: Services
            sites:
              - title: Dynacat
                url: http://127.0.0.1:8080
            update-interval: 5m
EOF
  msg_ok "Set up Dynacat"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/dynacat.service
[Unit]
Description=Dynacat Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/dynacat
ExecStart=/opt/dynacat/dynacat -config /opt/dynacat/config/dynacat.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now dynacat
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

  if [[ ! -f /opt/dynacat/dynacat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "dynacat" "Panonim/dynacat"; then
    msg_info "Stopping Service"
    systemctl stop dynacat
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/dynacat/config /opt/dynacat_config_backup
    cp -r /opt/dynacat/assets /opt/dynacat_assets_backup
    cp -r /opt/dynacat/data /opt/dynacat_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "dynacat" "Panonim/dynacat" "prebuild" "latest" "/opt/dynacat" "dynacat-linux-amd64.tar.gz"

    msg_info "Restoring Data"
    cp -r /opt/dynacat_config_backup/. /opt/dynacat/config
    cp -r /opt/dynacat_assets_backup/. /opt/dynacat/assets
    cp -r /opt/dynacat_data_backup/. /opt/dynacat/data
    rm -rf /opt/dynacat_config_backup /opt/dynacat_assets_backup /opt/dynacat_data_backup
    chmod +x /opt/dynacat/dynacat
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start dynacat
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# Dynamic URL resolved at runtime - shellcheck cannot follow\n# shellcheck disable=SC1090\nsource <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
