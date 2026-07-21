#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://traefik.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Traefik"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apt-transport-https
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "traefik" "traefik/traefik" "prebuild" "latest" "/usr/bin" "traefik_v*_linux_$(get_system_arch).tar.gz"
  mkdir -p /etc/traefik/{conf.d,ssl}

  msg_info "Creating Traefik configuration"
  cat << EOF > /etc/traefik/traefik.yaml
providers:
  file:
    directory: /etc/traefik/conf.d/

entryPoints:
  web:
    address: ':80'
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ':443'
    http:
      tls:
        certResolver: letsencrypt
  traefik:
    address: ':8080'

certificatesResolvers:
  letsencrypt:
    acme:
      email: "foo@bar.com"
      storage: /etc/traefik/ssl/acme.json
      tlsChallenge: {}

api:
  dashboard: true
  insecure: true

log:
  filePath: /var/log/traefik/traefik.log
  format: json
  level: INFO

accessLog:
  filePath: /var/log/traefik/traefik-access.log
  format: json
  filters:
    statusCodes:
      - "200"
      - "400-599"
    retryAttempts: true
    minDuration: "10ms"
  bufferingSize: 0
  fields:
    headers:
      defaultMode: drop
      names:
        User-Agent: keep
EOF
  msg_ok "Created Traefik configuration"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/traefik.service
[Unit]
Description=Traefik is an open-source Edge Router that makes publishing your services a fun and easy experience

[Service]
Type=notify
ExecStart=/usr/bin/traefik --configFile=/etc/traefik/traefik.yaml
Restart=on-failure
ExecReload=/bin/kill -USR1 $MAINPID

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now traefik
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/traefik.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "traefik" "traefik/traefik"; then
    msg_info "Stopping Service"
    systemctl stop traefik
    msg_ok "Stopped Service"
    fetch_and_deploy_gh_release "traefik" "traefik/traefik" "prebuild" "latest" "/usr/bin" "traefik_v*_linux_$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start traefik
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
