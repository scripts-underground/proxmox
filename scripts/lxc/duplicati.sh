#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/duplicati/duplicati/
# shellcheck disable=SC2034
APP="Duplicati"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    libice6 \
    libsm6 \
    libfontconfig1
  msg_ok "Installed Dependencies"

  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "duplicati" "duplicati/duplicati" "binary" "latest" "/opt/duplicati" "duplicati-*-linux-${ARCH}-gui.deb"

  msg_info "Configuring duplicati"
  DECRYPTKEY=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  ADMINPASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  cat << EOF > /root/duplicati.creds
Admin password = ${ADMINPASS}
Database encryption key = ${DECRYPTKEY}
EOF
  msg_ok "Configured duplicati"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/duplicati.service
[Unit]
Description=Duplicati Service
After=network.target

[Service]
ExecStart=/usr/bin/duplicati-server --webservice-interface=any --webservice-password=${ADMINPASS} --settings-encryption-key=${DECRYPTKEY}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now duplicati
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8200${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/duplicati-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "duplicati" "duplicati/duplicati"; then
    msg_info "Stopping Service"
    systemctl stop duplicati
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "duplicati" "duplicati/duplicati" "binary" "latest" "/opt/duplicati" "duplicati-*-linux-${ARCH}-gui.deb"

    msg_info "Starting Service"
    systemctl start duplicati
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
