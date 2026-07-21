#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: emoscardini (emoscardini)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/openziti/ziti

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="OpenZiti Controller"
var_tags="${var_tags:-network;openziti-controller}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing OpenZiti Controller"
  mkdir -p /usr/share/keyrings
  curl -fsSL https://get.openziti.io/tun/package-repos.gpg | gpg --dearmor -o /usr/share/keyrings/openziti.gpg
  cat << EOF > /etc/apt/sources.list.d/openziti.sources
Types: deb
URIs: https://packages.openziti.org/zitipax-openziti-deb-stable
Suites: debian
Components: main
Signed-By: /usr/share/keyrings/openziti.gpg
EOF
  $STD apt update
  $STD apt install -y openziti-controller openziti-console
  msg_ok "Installed OpenZiti Controller"

  read -r -p "${TAB3}Would you like to go through the auto configuration now? <y/N>" prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    GEN_FQDN="controller.${LOCAL_IP}.sslip.io"
    read -r -p "${TAB3}Please enter the controller FQDN [${GEN_FQDN}]: " ZITI_CTRL_ADVERTISED_ADDRESS
    ZITI_CTRL_ADVERTISED_ADDRESS=${ZITI_CTRL_ADVERTISED_ADDRESS:-$GEN_FQDN}
    read -r -p "${TAB3}Please enter the controller port [1280]: " ZITI_CTRL_ADVERTISED_PORT
    ZITI_CTRL_ADVERTISED_PORT=${ZITI_CTRL_ADVERTISED_PORT:-1280}
    read -r -p "${TAB3}Please enter the controller admin user [admin]: " ZITI_USER
    ZITI_USER=${ZITI_USER:-admin}
    GEN_PWD=$(head -c128 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^*_+~' | cut -c 1-12)
    read -r -p "${TAB3}Please enter the controller admin password [${GEN_PWD}]:" ZITI_PWD
    ZITI_PWD=${ZITI_PWD:-$GEN_PWD}
    CONFIG_FILE="/opt/openziti/etc/controller/bootstrap.env"
    sed -i "s|^ZITI_CTRL_ADVERTISED_ADDRESS=.*|ZITI_CTRL_ADVERTISED_ADDRESS='${ZITI_CTRL_ADVERTISED_ADDRESS}'|" "$CONFIG_FILE"
    sed -i "s|^ZITI_CTRL_ADVERTISED_PORT=.*|ZITI_CTRL_ADVERTISED_PORT='${ZITI_CTRL_ADVERTISED_PORT}'|" "$CONFIG_FILE"
    sed -i "s|^ZITI_USER=.*|ZITI_USER='${ZITI_USER}'|" "$CONFIG_FILE"
    sed -i "s|^ZITI_PWD=.*|ZITI_PWD='${ZITI_PWD}'|" "$CONFIG_FILE"
    env VERBOSE=0 bash /opt/openziti/etc/controller/bootstrap.bash
    msg_ok "Configuration Completed"
    systemctl enable -q --now ziti-controller
  else
    systemctl enable -q ziti-controller
    msg_error "Configuration not provided; Please run /opt/openziti/etc/controller/bootstrap.bash to configure the controller and restart the container"
  fi
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:<port>/zac${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/openziti ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated ${APP} LXC"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
