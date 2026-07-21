#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.passbolt.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Passbolt"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing dependencies"
  $STD apt install -y \
    apt-transport-https \
    python3-certbot-nginx \
    debconf-utils
  msg_ok "Installed dependencies"

  setup_mariadb
  MARIADB_DB_NAME="passboltdb" MARIADB_DB_USER="passbolt" setup_mariadb_db
  create_self_signed_cert

  setup_deb822_repo \
    "passbolt" \
    "https://keys.openpgp.org/pks/lookup?op=get&options=mr&search=0x3D1A0346C8E1802F774AEF21DE8B853FC155581D" \
    "https://download.passbolt.com/ce/debian" \
    "buster" \
    "stable"

  msg_info "Setting up Passbolt (Patience)"
  DEBIAN_FRONTEND=noninteractive
  export DEBIAN_FRONTEND
  echo passbolt-ce-server passbolt/mysql-configuration boolean true | debconf-set-selections
  echo passbolt-ce-server passbolt/mysql-passbolt-username string $MARIADB_DB_USER | debconf-set-selections
  echo passbolt-ce-server passbolt/mysql-passbolt-password password $MARIADB_DB_PASS | debconf-set-selections
  echo passbolt-ce-server passbolt/mysql-passbolt-password-repeat password $MARIADB_DB_PASS | debconf-set-selections
  echo passbolt-ce-server passbolt/mysql-passbolt-dbname string $MARIADB_DB_NAME | debconf-set-selections
  echo passbolt-ce-server passbolt/nginx-configuration boolean true | debconf-set-selections
  echo passbolt-ce-server passbolt/nginx-configuration-three-choices select manual | debconf-set-selections
  echo passbolt-ce-server passbolt/nginx-domain string $LOCAL_IP | debconf-set-selections
  echo passbolt-ce-server passbolt/nginx-certificate-file string /etc/ssl/passbolt/passbolt.crt | debconf-set-selections
  echo passbolt-ce-server passbolt/nginx-certificate-key-file string /etc/ssl/passbolt/passbolt.key | debconf-set-selections
  $STD apt install -y --no-install-recommends passbolt-ce-server
  sed -i 's/client_max_body_size[[:space:]]\+[0-9]\+M;/client_max_body_size        15M;/' /etc/nginx/sites-enabled/nginx-passbolt.conf
  systemctl reload nginx
  msg_ok "Setup Passbolt"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  setup_mariadb
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated $APP LXC"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
