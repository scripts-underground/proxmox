#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tremor021 (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/hakimel/reveal.js

# shellcheck disable=SC2034
APP="RevealJS"
var_tags="${var_tags:-documents;presentation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "revealjs" "hakimel/reveal.js" "tarball"

  msg_info "Configuring ${APP}"
  cd /opt/revealjs || exit
  $STD npm install
  sed -i 's/"vite"/"vite --host"/g' package.json
  msg_ok "Setup ${APP}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/revealjs.service
[Unit]
Description=Reveal.js Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/revealjs
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now revealjs
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/revealjs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "revealjs" "hakimel/reveal.js"; then
    msg_info "Stopping Service"
    systemctl stop revealjs
    msg_ok "Stopped Service"

    cp /opt/revealjs/index.html /opt
    fetch_and_deploy_gh_release "revealjs" "hakimel/reveal.js" "tarball"

    msg_info "Updating ${APP}"
    cd /opt/revealjs || exit
    $STD npm install
    cp -f /opt/index.html /opt/revealjs
    sed -i 's/"vite"/"vite --host"/g' package.json
    rm -f /opt/index.html
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start revealjs
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
