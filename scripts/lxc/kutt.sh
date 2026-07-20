#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tomfrenzel
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/thedevs-network/kutt

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Kutt"
var_tags="${var_tags:-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  echo "${TAB3}How would you like to handle SSL termination?"
  echo "${TAB3}[i]-Internal (self-signed SSL Certificate)   [e]-External (use your own reverse proxy)"
  read -rp "${TAB3}Enter your choice <i/e> (default: i): " ssl_choice
  ssl_choice=${ssl_choice:-i}
  case "${ssl_choice,,}" in
    i)
      DEFAULT_HOST="$LOCAL_IP"

      msg_info "Installing Dependencies"
      $STD apt install -y caddy
      msg_ok "Installed Dependencies"

      msg_info "Configuring Caddy"
      cat << EOF > /etc/caddy/Caddyfile
$LOCAL_IP {
    reverse_proxy localhost:3000
}
EOF
      systemctl restart caddy
      msg_ok "Configured Caddy"
      ;;
    e)
      read -r -p "${TAB3}Enter the hostname you want to use for Kutt (eg. kutt.example.com): " custom_host
      if [[ "$custom_host" ]]; then
        DEFAULT_HOST="$custom_host"
      fi
      ;;
  esac

  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "kutt" "thedevs-network/kutt" "tarball"

  msg_info "Configuring Kutt"
  cd /opt/kutt || exit
  cp .example.env ".env"
  sed -i "s|JWT_SECRET=|JWT_SECRET=$(openssl rand -base64 32)|g" ".env"
  sed -i "s|DEFAULT_DOMAIN=.*|DEFAULT_DOMAIN=$DEFAULT_HOST|g" ".env"
  $STD npm install
  $STD npm run migrate
  msg_ok "Configured Kutt"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/kutt.service
[Unit]
Description=Kutt server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/kutt
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kutt
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP} or https://<your-Kutt-domain>${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kutt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "kutt" "thedevs-network/kutt"; then
    msg_info "Stopping services"
    systemctl stop kutt
    msg_ok "Stopped services"

    msg_info "Backing up data"
    mkdir -p /opt/kutt-backup
    [ -d /opt/kutt/custom ] && cp -r /opt/kutt/custom /opt/kutt-backup/
    [ -d /opt/kutt/db ] && cp -r /opt/kutt/db /opt/kutt-backup/
    cp /opt/kutt/.env /opt/kutt-backup/
    msg_ok "Backed up data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "kutt" "thedevs-network/kutt" "tarball" "latest"

    msg_info "Restoring data"
    [ -d /opt/kutt-backup/custom ] && cp -r /opt/kutt-backup/custom /opt/kutt/
    [ -d /opt/kutt-backup/db ] && cp -r /opt/kutt-backup/db /opt/kutt/
    [ -f /opt/kutt-backup/.env ] && cp /opt/kutt-backup/.env /opt/kutt/
    rm -rf /opt/kutt-backup
    msg_ok "Restored data"

    msg_info "Configuring Kutt"
    cd /opt/kutt || exit
    $STD npm install
    $STD npm run migrate
    msg_ok "Configured Kutt"

    msg_info "Starting services"
    systemctl start kutt
    msg_ok "Started services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
