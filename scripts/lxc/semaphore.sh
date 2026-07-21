#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://semaphoreui.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Semaphore"
var_tags="${var_tags:-dev_ops}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    ansible
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "semaphore" "semaphoreui/semaphore" "binary" "latest" "/opt/semaphore" "semaphore_*_linux_$(get_system_arch).deb"

  msg_info "Configuring Semaphore"
  mkdir -p /opt/semaphore
  cd /opt/semaphore || exit
  SEM_HASH=$(openssl rand -base64 32)
  SEM_ENCRYPTION=$(openssl rand -base64 32)
  SEM_KEY=$(openssl rand -base64 32)
  SEM_PW=$(openssl rand -base64 12)
  cat << EOF > /opt/semaphore/config.json
{
  "sqlite": {
    "host": "/opt/semaphore/database.sqlite"
  },
  "dialect": "sqlite",
  "tmp_path": "/opt/semaphore/tmp",
  "cookie_hash": "${SEM_HASH}",
  "cookie_encryption": "${SEM_ENCRYPTION}",
  "access_key_encryption": "${SEM_KEY}"
}
EOF
  $STD semaphore user add --admin --login admin --email admin@community-scripts.org --name Administrator --password "${SEM_PW}" --config /opt/semaphore/config.json
  echo "${SEM_PW}" > ~/semaphore.creds
  msg_ok "Setup Semaphore"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/semaphore.service
[Unit]
Description=Semaphore UI
Documentation=https://docs.semaphoreui.com/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/semaphore server --config /opt/semaphore/config.json
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now semaphore
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/semaphore.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "semaphore" "semaphoreui/semaphore"; then
    if [[ -f /opt/semaphore/semaphore_db.bolt ]]; then
      msg_warn "WARNING: Due to bugs with BoltDB database, update script will move your application"
      msg_warn "to use SQLite database instead. Make sure you have a backup of your data!"
      echo ""
      read -r -p "${TAB3}Do you want to continue? (y/N): " CONFIRM
      if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 0
      else
        msg_info "Moving from BoltDB to SQLite"
        sed -i \
          -e 's|"bolt": {|"sqlite": {|' \
          -e 's|/semaphore_db.bolt"|/database.sqlite"|' \
          -e '/semaphore_db.bolt/d' \
          -e '/"dialect"/d' \
          -e '/^  },$/a\  "dialect": "sqlite",' \
          /opt/semaphore/config.json
        msg_ok "Moved from BoltDB to SQLite"
      fi
    fi

    msg_info "Stopping Service"
    systemctl stop semaphore
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "semaphore" "semaphoreui/semaphore" "binary" "latest" "/opt/semaphore" "semaphore_*_linux_$(get_system_arch).deb"

    if [[ -f /opt/semaphore/semaphore_db.bolt ]]; then
      $STD semaphore migrate --from-boltdb /opt/semaphore/semaphore_db.bolt --config /opt/semaphore/config.json
      rm -f /opt/semaphore/semaphore_db.bolt
    fi

    msg_info "Starting Service"
    systemctl start semaphore
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
