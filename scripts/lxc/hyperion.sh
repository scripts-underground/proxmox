#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://hyperion-project.org/forum/

# shellcheck disable=SC2034
APP="Hyperion"
var_tags="${var_tags:-ambient-lightning}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Setting up Hyperion repository"
  setup_deb822_repo \
    "hyperion" \
    "https://releases.hyperion-project.org/hyperion.pub.key" \
    "https://apt.releases.hyperion-project.org" \
    "$(get_os_info codename)"
  msg_ok "Set up Hyperion repository"

  msg_info "Installing Hyperion"
  $STD apt install -y hyperion
  mkdir -p /etc/systemd/system/hyperion@.service.d
  cat << EOF > /etc/systemd/system/hyperion@.service.d/override.conf
[Unit]
Requisite=
EOF
  systemctl daemon-reload
  systemctl enable -q --now hyperion@root
  msg_ok "Installed Hyperion"

  setup_hwaccel
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/apt/sources.list.d/hyperion.list ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt install -y hyperion
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
