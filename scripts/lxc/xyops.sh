#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pixlcore/xyops

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="xyOps"
var_tags="${var_tags:-scheduler;automation;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3 \
    python3-setuptools \
    pkg-config \
    libssl-dev \
    zlib1g-dev
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "xyops" "pixlcore/xyops" "tarball"

  msg_info "Building Application"
  cd /opt/xyops || exit
  $STD npm install
  $STD node bin/build.js dist
  chmod 644 /opt/xyops/node_modules/useragent-ng/lib/regexps.js
  msg_ok "Built Application"

  fetch_and_deploy_gh_release "xysat" "pixlcore/xysat" "tarball" "latest" "/opt/xyops/satellite"

  msg_info "Building xySat Satellite"
  cd /opt/xyops/satellite || exit
  $STD npm install
  msg_ok "Built xySat Satellite"

  msg_info "Setting up Directories"
  mkdir -p /opt/xyops/data /opt/xyops/logs /opt/xyops/temp /opt/xyops/conf
  msg_ok "Set up Directories"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/xyops.service
[Unit]
Description=xyOps Task Scheduler and Server Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/xyops
Environment=XYOPS_foreground=1
ExecStart=/usr/bin/node /opt/xyops/lib/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now xyops
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5522${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/xyops ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "xyops" "pixlcore/xyops"; then
    msg_info "Stopping Service"
    systemctl stop xyops
    msg_ok "Stopped Service"

    create_backup /opt/xyops/data /opt/xyops/conf

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "xyops" "pixlcore/xyops" "tarball"

    restore_backup

    msg_info "Rebuilding Application"
    cd /opt/xyops || exit
    $STD npm install
    $STD node bin/build.js dist
    chmod 644 /opt/xyops/node_modules/useragent-ng/lib/regexps.js
    msg_ok "Rebuilt Application"

    msg_info "Starting Service"
    systemctl start xyops
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
