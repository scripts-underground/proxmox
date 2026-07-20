#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://garagehq.deuxfleurs.fr/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Garage"
var_tags="${var_tags:-storage;object-storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt-get update
  $STD apt-get install -y curl jq openssl
  msg_ok "Installed Dependencies"

  msg_info "Installing Garage"
  ARCH=$(uname -m)
  GARAGE_RELEASE=$(curl -s https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
  curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_RELEASE}/${ARCH}-unknown-linux-musl/garage" -o /usr/local/bin/garage
  chmod +x /usr/local/bin/garage
  msg_ok "Installed Garage"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/garage.service
[Unit]
Description=Garage Object Storage
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/garage server /etc/garage/garage.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now garage
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3903${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/garage ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated $APP LXC"

  ARCH=$(uname -m)
  GARAGE_RELEASE=$(curl -s https://api.github.com/repos/deuxfleurs-org/garage/tags | jq -r '.[0].name')
  msg_info "Updating Garage to ${GARAGE_RELEASE}"
  curl -fsSL "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_RELEASE}/${ARCH}-unknown-linux-musl/garage" -o /usr/local/bin/garage
  chmod +x /usr/local/bin/garage
  msg_ok "Updated Garage to ${GARAGE_RELEASE}"

  systemctl restart garage
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
