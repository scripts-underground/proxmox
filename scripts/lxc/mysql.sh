#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.mysql.com/products/community

# shellcheck disable=SC2034
APP="MySQL"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y lsb-release
  msg_ok "Installed Dependencies"

  RELEASE_REPO="mysql-8.0"
  RELEASE_AUTH="mysql_native_password"
  read -r -p "${TAB3}Would you like to install the MySQL 8.4 LTS release instead of MySQL 8.0 (bug fix track; EOL April-2026)? <y/N> " prompt
  if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
    RELEASE_REPO="mysql-8.4-lts"
    RELEASE_AUTH="caching_sha2_password"
  fi

  msg_info "Installing MySQL"
  curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --dearmor -o /usr/share/keyrings/mysql.gpg
  if [[ "$(lsb_release -si)" == "Debian" ]]; then
    cat << EOF > /etc/apt/sources.list.d/mysql.sources
Types: deb
URIs: http://repo.mysql.com/apt/debian
Suites: $(lsb_release -sc)
Components: ${RELEASE_REPO}
Signed-By: /usr/share/keyrings/mysql.gpg
EOF
  else
    cat << EOF > /etc/apt/sources.list.d/mysql.sources
Types: deb
URIs: http://repo.mysql.com/apt/ubuntu
Suites: $(lsb_release -sc)
Components: ${RELEASE_REPO}
Signed-By: /usr/share/keyrings/mysql.gpg
EOF
  fi
  $STD apt update
  export DEBIAN_FRONTEND=noninteractive
  $STD apt install -y mysql-community-client mysql-community-server
  msg_ok "Installed MySQL"

  msg_info "Configuring MySQL Server"
  ADMIN_PASS=$(openssl rand -base64 18 | cut -c1-13)
  $STD mysql -uroot -p"$ADMIN_PASS" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH $RELEASE_AUTH BY '$ADMIN_PASS'; FLUSH PRIVILEGES;"
  cat << EOF > /root/mysql.creds
MySQL user: root
MySQL password: $ADMIN_PASS
EOF
  msg_ok "MySQL Server configured"

  read -r -p "${TAB3}Would you like to add PhpMyAdmin? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/phpmyadmin.sh)"
  fi

  msg_info "Starting Service"
  systemctl enable -q --now mysql
  msg_ok "Service started"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3306${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/share/keyrings/mysql.gpg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
