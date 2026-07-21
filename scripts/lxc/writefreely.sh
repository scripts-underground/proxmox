#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: StellaeAlis
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/writefreely/writefreely
# shellcheck disable=SC2034
APP="WriteFreely"
var_tags="${var_tags:-writing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y crudini
  msg_ok "Installed Dependencies"

  setup_mariadb
  MARIADB_DB_NAME="writefreely" MARIADB_DB_USER="writefreely" setup_mariadb_db
  fetch_and_deploy_gh_release "writefreely" "writefreely/writefreely" "prebuild" "latest" "/opt/writefreely" "writefreely_*_linux_$(get_system_arch).tar.gz"

  msg_info "Setting up WriteFreely"
  cd /opt/writefreely || exit
  $STD ./writefreely config generate
  $STD ./writefreely keys generate
  msg_ok "Setup WriteFreely"

  msg_info "Configuring WriteFreely"
  $STD crudini --set config.ini server port 80
  $STD crudini --set config.ini server bind $LOCAL_IP
  $STD crudini --set config.ini database username $MARIADB_DB_USER
  $STD crudini --set config.ini database password $MARIADB_DB_PASS
  $STD crudini --set config.ini database database $MARIADB_DB_NAME
  $STD crudini --set config.ini app host http://$LOCAL_IP:80
  $STD ./writefreely db init
  ln -s /opt/writefreely/writefreely /usr/local/bin/writefreely
  msg_ok "Configured WriteFreely"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/writefreely.service
[Unit]
Description=WriteFreely Service
After=syslog.target network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/writefreely
ExecStart=/opt/writefreely/writefreely
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now writefreely
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
  if [[ ! -d /opt/writefreely ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "writefreely" "writefreely/writefreely"; then
    msg_info "Stopping Services"
    systemctl stop writefreely
    msg_ok "Stopped Services"

    msg_info "Creating Backup"
    mkdir -p /tmp/writefreely_backup
    cp /opt/writefreely/keys /tmp/writefreely_backup/ 2> /dev/null
    cp /opt/writefreely/config.ini /tmp/writefreely_backup/ 2> /dev/null
    msg_ok "Created Backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "writefreely" "writefreely/writefreely" "prebuild" "latest" "/opt/writefreely" "writefreely_*_linux_$(get_system_arch).tar.gz"

    msg_info "Restoring Data"
    cp /tmp/writefreely_backup/config.ini /opt/writefreely/ 2> /dev/null
    cp /tmp/writefreely_backup/keys/* /opt/writefreely/keys/ 2> /dev/null
    rm -rf /tmp/writefreely_backup
    msg_ok "Restored Data"

    msg_info "Running Post-Update Tasks"
    cd /opt/writefreely || exit
    $STD ./writefreely db migrate
    ln -s /opt/writefreely/writefreely /usr/local/bin/writefreely
    msg_ok "Ran Post-Update Tasks"

    msg_info "Starting Services"
    systemctl start writefreely
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
