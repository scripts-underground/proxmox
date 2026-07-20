#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://docs.craftycontrol.com/pages/getting-started/installation/linux/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Crafty-Controller"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up TemurinJDK"
  setup_java
  $STD apt install -y temurin-{8,11,17,21,25}-jre
  $STD update-alternatives --set java "/usr/lib/jvm/temurin-25-jre-$(get_system_arch)/bin/java"
  msg_ok "Installed TemurinJDK"

  msg_info "Setup Python3"
  $STD apt install -y \
    python3-dev \
    python3-pip \
    python3-venv
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Setup Python3"

  useradd crafty -m -s /bin/bash
  mkdir -p /opt/crafty-controller/crafty /opt/crafty-controller/server
  fetch_and_deploy_gl_release "Crafty-Controller" "crafty-controller/crafty-4" "tarball" "latest" "/opt/crafty-controller/crafty/crafty-4"

  msg_info "Installing Crafty-Controller dependencies (Patience)"
  cd /opt/crafty-controller/crafty || exit
  python3 -m venv .venv
  chown -R crafty:crafty /opt/crafty-controller/
  $STD sudo -u crafty bash -c '
    source /opt/crafty-controller/crafty/.venv/bin/activate
    cd /opt/crafty-controller/crafty/crafty-4
    pip3 install --no-cache-dir -r requirements.txt
  '
  msg_ok "Installed Crafty-Controller dependencies"

  msg_info "Setting up service"
  cat << EOF > /etc/systemd/system/crafty-controller.service
[Unit]
Description=Crafty 4
After=network.target

[Service]
Type=simple
User=crafty
WorkingDirectory=/opt/crafty-controller/crafty/crafty-4
Environment=PATH=/usr/lib/jvm/temurin-25-jre-$(get_system_arch)/bin:/opt/crafty-controller/crafty/.venv/bin:$PATH
ExecStart=/opt/crafty-controller/crafty/.venv/bin/python3 main.py -d
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now crafty-controller
  CREDS_FILE="/opt/crafty-controller/crafty/crafty-4/app/config/default-creds.txt"
  for _ in $(seq 1 30); do
    [[ -f "$CREDS_FILE" ]] && break
    sleep 2
  done
  if [[ -f "$CREDS_FILE" ]]; then
    cat << EOF > ~/crafty-controller.creds
Crafty-Controller-Credentials
Username: $(grep -oP '(?<="username": ")[^"]*' "$CREDS_FILE")
Password: $(grep -oP '(?<="password": ")[^"]*' "$CREDS_FILE")
EOF
  fi
  msg_ok "Service started"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"
  if [[ -f ~/crafty-controller.creds ]]; then
    echo -e "${INFO}${YW}Default Credentials:${CL}"
    cat ~/crafty-controller.creds
  fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/crafty-controller ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gl_release "Crafty-Controller" "crafty-controller/crafty-4"; then
    msg_info "Stopping Crafty-Controller"
    systemctl stop crafty-controller
    msg_ok "Stopped Crafty-Controller"

    create_backup \
      "/opt/crafty-controller/crafty/crafty-4/app/config/db" \
      "/opt/crafty-controller/crafty/crafty-4/app/config/config.json" \
      "/opt/crafty-controller/crafty/crafty-4/app/config/web" \
      "/opt/crafty-controller/crafty/crafty-4/servers" \
      "/opt/crafty-controller/crafty/crafty-4/backups" \
      "/opt/crafty-controller/crafty/crafty-4/import"

    CLEAN_INSTALL=1 fetch_and_deploy_gl_release "Crafty-Controller" "crafty-controller/crafty-4" "tarball" "latest" "/opt/crafty-controller/crafty/crafty-4"

    restore_backup

    msg_info "Updating TemurinJDK"
    setup_java
    $STD apt install -y temurin-{8,11,17,21,25}-jre
    $STD update-alternatives --set java "/usr/lib/jvm/temurin-25-jre-$(get_system_arch)/bin/java"
    msg_ok "Updated TemurinJDK"

    msg_info "Updating Python dependencies"
    chown -R crafty:crafty /opt/crafty-controller
    cd /opt/crafty-controller/crafty/crafty-4 || exit
    $STD sudo -u crafty bash -c '
      source /opt/crafty-controller/crafty/.venv/bin/activate
      pip3 install --no-cache-dir -r requirements.txt
    '
    msg_ok "Updated Python dependencies"

    msg_info "Starting Crafty-Controller"
    systemctl start crafty-controller
    msg_ok "Started Crafty-Controller"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
