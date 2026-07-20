#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: John Lombardo (programbo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/thelastoutpostworkshop/ESPConnect

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ESPConnect"
var_tags="${var_tags:-iot;esp32;flash}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y nginx
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "espconnect" "thelastoutpostworkshop/ESPConnect" "prebuild" "latest" "/opt/espconnect" "dist.zip"
  create_self_signed_cert

  msg_info "Configuring Nginx"
  mkdir -p /etc/ssl/private
  cat << 'EOF' > /etc/nginx/sites-available/espconnect
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/ssl/espconnect/espconnect.crt;
    ssl_certificate_key /etc/ssl/espconnect/espconnect.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /opt/espconnect;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/espconnect /etc/nginx/sites-enabled/espconnect
  rm -f /etc/nginx/sites-enabled/default
  $STD nginx -t
  systemctl enable -q nginx
  systemctl restart nginx
  msg_ok "Configured Nginx"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/espconnect ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "espconnect" "thelastoutpostworkshop/ESPConnect"; then
    msg_info "Stopping Nginx"
    systemctl stop nginx
    msg_ok "Stopped Nginx"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "espconnect" "thelastoutpostworkshop/ESPConnect" "prebuild" "latest" "/opt/espconnect" "dist.zip"

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
