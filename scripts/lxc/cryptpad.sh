#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/cryptpad/cryptpad

# shellcheck disable=SC2034
APP="CryptPad"
var_tags="${var_tags:-docs;office}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  read -rp "Install OnlyOffice components instead of CKEditor? (Y/N): " onlyoffice
  fetch_and_deploy_gh_release "cryptpad" "cryptpad/cryptpad" "tarball"

  msg_info "Setup CryptPad"
  cd /opt/cryptpad || exit
  $STD npm ci
  $STD npm run install:components
  if [[ "$onlyoffice" =~ ^[Yy]$ ]]; then
    $STD bash -c "./install-onlyoffice.sh --accept-license"
  fi
  cp config/config.example.js config/config.js
  sed -i "51s/localhost/${LOCAL_IP}/g" /opt/cryptpad/config/config.js
  sed -i "80s#//httpAddress: 'localhost'#httpAddress: '0.0.0.0'#g" /opt/cryptpad/config/config.js
  $STD npm run build
  msg_ok "Setup CryptPad"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/cryptpad.service
[Unit]
Description=CryptPad Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cryptpad
ExecStart=/usr/bin/node server
Environment='PWD="/opt/cryptpad"'
StandardOutput=journal
StandardError=journal+console
LimitNOFILE=1000000
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cryptpad
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
  echo -e "${INFO}${YW} After installation, run the following to get your admin token URL:${CL}"
  echo -e "${TAB}${BGN}systemctl status cryptpad.service${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d "/opt/cryptpad" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "cryptpad" "cryptpad/cryptpad"; then
    msg_info "Stopping Service"
    systemctl stop cryptpad
    msg_ok "Stopped Service"

    create_backup /opt/cryptpad/config/config.js \
      /opt/cryptpad/blob \
      /opt/cryptpad/block \
      /opt/cryptpad/customize \
      /opt/cryptpad/data \
      /opt/cryptpad/datastore \
      /opt/cryptpad/www/common/onlyoffice/dist \
      /opt/cryptpad/onlyoffice-conf

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cryptpad" "cryptpad/cryptpad" "tarball"

    restore_backup

    msg_info "Updating CryptPad"
    cd /opt/cryptpad || exit
    $STD npm ci
    $STD npm run install:components
    if [ -f "/opt/cryptpad/install-onlyoffice.sh" ]; then
      $STD bash /opt/cryptpad/install-onlyoffice.sh --accept-license
    fi
    $STD npm run build
    msg_ok "Updated CryptPad"

    msg_info "Starting Service"
    systemctl start cryptpad
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
