#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nginxui.com | Github: https://github.com/0xJacky/nginx-ui

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Nginx-UI"
var_tags="${var_tags:-webserver;nginx;proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nginx \
    logrotate
  msg_ok "Installed Dependencies"

  msg_info "Installing Nginx-UI"
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    NUI_ARCH="64"
  elif [ "$ARCH" = "aarch64" ]; then
    NUI_ARCH="arm64-v8a"
  fi
  fetch_and_deploy_gh_release "nginx-ui" "0xJacky/nginx-ui" "prebuild" "latest" "/opt/nginx-ui" "nginx-ui-linux-${NUI_ARCH}.tar.gz"
  cp /opt/nginx-ui/nginx-ui /usr/local/bin/nginx-ui
  chmod +x /usr/local/bin/nginx-ui
  rm -rf /opt/nginx-ui
  msg_ok "Installed Nginx-UI"

  msg_info "Configuring Nginx-UI"
  mkdir -p /usr/local/etc/nginx-ui
  cat << EOF > /usr/local/etc/nginx-ui/app.ini
[app]
PageSize = 10

[server]
Host = 0.0.0.0
Port = 9000
RunMode = release

[cert]
HTTPChallengePort = 9180

[terminal]
StartCmd = login
EOF
  msg_ok "Configured Nginx-UI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/nginx-ui.service
[Unit]
Description=Another WebUI for Nginx
Documentation=https://nginxui.com
After=network.target nginx.service

[Service]
Type=simple
ExecStart=/usr/local/bin/nginx-ui --config /usr/local/etc/nginx-ui/app.ini
RuntimeDirectory=nginx-ui
WorkingDirectory=/var/run/nginx-ui
Restart=on-failure
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  msg_ok "Created Service"

  msg_info "Starting Service"
  systemctl enable -q --now nginx-ui
  rm -rf /etc/nginx/sites-enabled/default
  msg_ok "Started Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/nginx-ui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nginx-ui" "0xJacky/nginx-ui"; then
    msg_info "Stopping Service"
    systemctl stop nginx-ui
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /usr/local/etc/nginx-ui/app.ini /tmp/nginx-ui-app.ini.bak
    msg_ok "Backed up Configuration"

    msg_info "Updating Binary"
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      NUI_ARCH="64"
    elif [ "$ARCH" = "aarch64" ]; then
      NUI_ARCH="arm64-v8a"
    fi
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nginx-ui" "0xJacky/nginx-ui" "prebuild" "latest" "/opt/nginx-ui" "nginx-ui-linux-${NUI_ARCH}.tar.gz"
    cp /opt/nginx-ui/nginx-ui /usr/local/bin/nginx-ui
    chmod +x /usr/local/bin/nginx-ui
    rm -rf /opt/nginx-ui
    msg_ok "Updated Binary"

    msg_info "Restoring Configuration"
    mv /tmp/nginx-ui-app.ini.bak /usr/local/etc/nginx-ui/app.ini
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start nginx-ui
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
