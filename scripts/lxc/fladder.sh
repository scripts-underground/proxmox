#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: wendyliga
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/DonutWare/Fladder

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Fladder"
var_tags="${var_tags:-media;video;streaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "Fladder" "DonutWare/Fladder" "prebuild" "latest" "/opt/fladder" "Fladder-Web-*.zip"

  msg_info "Configuring Nginx"
  cat << 'EOF' > /etc/nginx/sites-available/fladder
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /opt/fladder;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/fladder /etc/nginx/sites-enabled/fladder
  rm -f /etc/nginx/sites-enabled/default
  systemctl enable -q nginx
  systemctl start nginx
  msg_ok "Configured Nginx"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/fladder ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Fladder" "DonutWare/Fladder"; then
    msg_info "Stopping Nginx"
    systemctl stop nginx
    msg_ok "Stopped Nginx"

    if [[ -f /opt/fladder/assets/config/config.json ]]; then
      msg_info "Backing up configuration"
      cp /opt/fladder/assets/config/config.json /tmp/fladder_config.json.bak
      msg_ok "Configuration backed up"
    fi

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Fladder" "DonutWare/Fladder" "prebuild" "latest" "/opt/fladder" "Fladder-Web-*.zip"

    if [[ -f /tmp/fladder_config.json.bak ]]; then
      msg_info "Restoring configuration"
      mkdir -p /opt/fladder/assets/config
      cp /tmp/fladder_config.json.bak /opt/fladder/assets/config/config.json
      rm -f /tmp/fladder_config.json.bak
      msg_ok "Configuration restored"
    fi

    msg_info "Starting Nginx"
    systemctl start nginx
    msg_ok "Started Nginx"

    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
