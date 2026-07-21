#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bvdberg01 (bvdberg01)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Luzifer/ots

# shellcheck disable=SC2034
APP="OTS"
var_tags="${var_tags:-secrets-sharer}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y redis-server nginx
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "ots" "Luzifer/ots" "prebuild" "latest" "/opt/ots" "ots_linux_$(get_system_arch).tgz"

  msg_info "Creating self-signed certificate"
  mkdir -p /etc/ssl/ots
  $STD openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/ssl/ots/ots.key \
    -out /etc/ssl/ots/ots.crt \
    -subj "/CN=ots"
  msg_ok "Created self-signed certificate"

  msg_info "Setup OTS"
  cat << EOF > /opt/ots/.env
LISTEN=127.0.0.1:3000
REDIS_URL=redis://127.0.0.1:6379
SECRET_EXPIRY=604800
STORAGE_TYPE=redis
EOF
  msg_ok "Setup OTS"

  msg_info "Setting up nginx"
  cat << EOF > /etc/nginx/sites-available/ots.conf
server {
    listen 80;
    listen [::]:80;
    server_name ots;
    return 301 https://\$host\$request_uri;
}
server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ots;

  ssl_certificate /etc/ssl/ots/ots.crt;
  ssl_certificate_key /etc/ssl/ots/ots.key;

  location / {
    add_header X-Robots-Tag noindex;

    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    client_max_body_size 64M;
    proxy_pass http://127.0.0.1:3000/;
  }
}
EOF

  ln -s /etc/nginx/sites-available/ots.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  msg_ok "Configured nginx"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/ots.service
[Unit]
Description=One-Time-Secret Service
After=network-online.target
Requires=network-online.target

[Service]
EnvironmentFile=/opt/ots/.env
ExecStart=/opt/ots/ots
Restart=Always
RestartSecs=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ots
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/ots ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ots" "Luzifer/ots"; then
    msg_info "Stopping Services"
    systemctl stop ots
    systemctl stop nginx
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ots" "Luzifer/ots" "prebuild" "latest" "/opt/ots" "ots_linux_$(get_system_arch).tgz"

    msg_info "Starting Services"
    systemctl start ots
    systemctl start nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
