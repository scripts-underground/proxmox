#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://graylog.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Graylog"
var_tags="${var_tags:-logging}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function pre_build_script() {
  if [[ $(sysctl -n vm.max_map_count 2> /dev/null) -lt 262144 ]]; then
    sysctl -w vm.max_map_count=262144 > /dev/null 2>&1
    echo "vm.max_map_count=262144" > /etc/sysctl.d/graylog.conf
  fi
}

function install_script() {
  MONGO_VERSION="8.2" setup_mongodb

  msg_info "Setup Graylog Data Node"
  PASSWORD_SECRET=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
  curl_download "/tmp/graylog-7.0-repository_latest.deb" "https://packages.graylog2.org/repo/packages/graylog-7.0-repository_latest.deb"
  $STD dpkg -i /tmp/graylog-7.0-repository_latest.deb
  $STD apt update
  $STD apt install -y graylog-datanode
  sed -i "s/password_secret =/password_secret = $PASSWORD_SECRET/g" /etc/graylog/datanode/datanode.conf
  systemctl enable -q --now graylog-datanode
  msg_ok "Setup Graylog Data Node"

  msg_info "Setup Graylog Server"
  $STD apt install -y graylog-server
  ROOT_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
  cat << EOF > ~/graylog.creds
Graylog Credentials
Admin User: admin
Admin Password: ${ROOT_PASSWORD}
EOF
  ROOT_PASSWORD=$(echo -n "$ROOT_PASSWORD" | shasum -a 256 | awk '{print $1}')
  sed -i "s/password_secret =/password_secret = $PASSWORD_SECRET/g" /etc/graylog/server/server.conf
  sed -i "s/root_password_sha2 =/root_password_sha2 = $ROOT_PASSWORD/g" /etc/graylog/server/server.conf
  sed -i 's/#http_bind_address = 127.0.0.1.*/http_bind_address = 0.0.0.0:9000/g' /etc/graylog/server/server.conf
  systemctl enable -q --now graylog-server
  sleep 5
  sed -i "s/0\.0\.0\.0:9000/$LOCAL_IP:9000/g" /var/log/graylog-server/server.log
  msg_ok "Setup Graylog Server"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9000${CL}"
  echo -e "${INFO}${YW}Admin Login: admin / see ~/graylog.creds in container${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /etc/graylog ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop graylog-datanode
  systemctl stop graylog-server
  msg_ok "Stopped Service"

  CURRENT_VERSION=$(apt list --installed 2> /dev/null | grep graylog-server | grep -oP '\d+\.\d+\.\d+')

  if dpkg --compare-versions "$CURRENT_VERSION" lt "6.3"; then
    MONGO_VERSION="8.2" setup_mongodb

    msg_info "Updating Graylog"
    $STD apt update
    $STD apt upgrade -y
    curl_download "/tmp/graylog-7.0-repository_latest.deb" "https://packages.graylog2.org/repo/packages/graylog-7.0-repository_latest.deb"
    $STD dpkg -i /tmp/graylog-7.0-repository_latest.deb
    $STD apt update
    ensure_dependencies graylog-server graylog-datanode
    rm -f /tmp/graylog-7.0-repository_latest.deb
    msg_ok "Updated Graylog"
  elif dpkg --compare-versions "$CURRENT_VERSION" ge "7.0"; then
    msg_info "Updating Graylog"
    $STD apt update
    $STD apt upgrade -y
    msg_ok "Updated Graylog"
  fi

  msg_info "Starting Service"
  systemctl start graylog-datanode
  systemctl start graylog-server
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
