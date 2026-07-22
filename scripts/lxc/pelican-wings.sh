#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pelican-dev/wings

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Pelican-Wings"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "wings" "pelican-dev/wings" "singlefile" "latest" "/usr/local/bin" "wings_linux_$(get_system_arch)"
  mkdir -p /etc/pelican /var/run/wings

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/wings.service
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now wings
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/wings ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wings" "pelican-dev/wings"; then
    msg_info "Stopping Service"
    systemctl stop wings
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "wings" "pelican-dev/wings" "singlefile" "latest" "/usr/local/bin" "wings_linux_$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start wings
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
