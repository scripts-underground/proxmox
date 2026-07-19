#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: cobalt (cobaltgit)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://caddyserver.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Caddy"
var_tags="${var_tags:-webserver}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Caddy"
  $STD apk add --no-cache caddy caddy-openrc
  cat << EOF > /etc/caddy/Caddyfile
:80 {
  root * /var/www/html
  file_server
}
EOF
  mkdir -p /var/www/html
  cat << EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
  <head>
    <title>Caddy works!</title>
  </head>
  <body>
    <h1>Hello Caddy!</h1>
    <p>For more information, refer to the Caddy <a href="https://caddyserver.com/docs/">documentation</a><p>
  </body>
</html>
EOF
  msg_ok "Installed Caddy"

  read -r -p "${TAB3}Would you like to install xCaddy Addon? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | cut -c3-)" setup_go
    msg_info "Setup xCaddy"
    cd /opt || exit
    RELEASE=$(curl -fsSL https://api.github.com/repos/caddyserver/xcaddy/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
    curl -fsSL "https://github.com/caddyserver/xcaddy/releases/download/${RELEASE}/xcaddy_${RELEASE:1}_linux_amd64.tar.gz" -o "xcaddy_${RELEASE:1}_linux_amd64.tar.gz"
    $STD tar xzf xcaddy_"${RELEASE:1}"_linux_amd64.tar.gz -C /usr/local/bin xcaddy
    rm -rf /opt/xcaddy*
    $STD xcaddy build
    msg_ok "Setup xCaddy"
  fi

  msg_info "Enabling Caddy Service"
  $STD rc-update add caddy default
  msg_ok "Enabled Caddy Service"

  msg_info "Starting Caddy"
  $STD service caddy start
  msg_ok "Started Caddy"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /etc/caddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Caddy"
  rc-service caddy restart
  msg_ok "Restarted Caddy"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
