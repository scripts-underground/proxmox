#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Dolibarr/dolibarr/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Dolibarr"
var_tags="${var_tags:-business-erp}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    php-imap \
    debconf-utils
  msg_ok "Installed Dependencies"

  setup_mariadb

  msg_info "Setting up Database"
  ROOT_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
  $STD mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASS'; flush privileges;"
  cat << EOF > ~/dolibarr.creds
Dolibarr DB Credentials
MariaDB Root Password: $ROOT_PASS
EOF
  msg_ok "Set up database"

  msg_info "Setup Dolibarr"
  BASE="https://sourceforge.net/projects/dolibarr/files/Dolibarr%20installer%20for%20Debian-Ubuntu%20(DoliDeb)/"
  RELEASE=$(curl -fsSL "$BASE" | grep -oP '(?<=/Dolibarr%20installer%20for%20Debian-Ubuntu%20%28DoliDeb%29/)\d+(\.\d+)+(?=/)' | sort -V | tail -n1)
  FILE=$(curl -fsSL "${BASE}${RELEASE}/" | grep -oP 'dolibarr_[^"]+_all.deb' | head -n1)
  curl -fsSL "https://altushost-swe.dl.sourceforge.net/project/dolibarr/Dolibarr%20installer%20for%20Debian-Ubuntu%20(DoliDeb)/${RELEASE}/${FILE}?viasf=1" -o "${FILE}"
  echo "dolibarr dolibarr/reconfigure-webserver multiselect apache2" | debconf-set-selections
  $STD apt install ./"$FILE" -y
  $STD apt install -f
  rm -rf "$FILE"
  echo "${RELEASE}" > "/opt/${APP}_version.txt"
  msg_ok "Setup Dolibarr"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Dolibarr"
  BASE="https://sourceforge.net/projects/dolibarr/files/Dolibarr%20installer%20for%20Debian-Ubuntu%20(DoliDeb)/"
  RELEASE=$(curl -fsSL "$BASE" | grep -oP '(?<=/Dolibarr%20installer%20for%20Debian-Ubuntu%20%28DoliDeb%29/)\d+(\.\d+)+(?=/)' | sort -V | tail -n1)
  FILE=$(curl -fsSL "${BASE}${RELEASE}/" | grep -oP 'dolibarr_[^"]+_all.deb' | head -n1)
  curl -fsSL "https://altushost-swe.dl.sourceforge.net/project/dolibarr/Dolibarr%20installer%20for%20Debian-Ubuntu%20(DoliDeb)/${RELEASE}/${FILE}?viasf=1" -o "${FILE}"
  echo "dolibarr dolibarr/reconfigure-webserver multiselect apache2" | debconf-set-selections
  $STD apt install ./"$FILE" -y
  $STD apt install -f
  rm -rf "$FILE"
  echo "${RELEASE}" > "/opt/${APP}_version.txt"
  msg_ok "Updated Dolibarr"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
