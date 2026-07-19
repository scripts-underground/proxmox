#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/rustdesk/rustdesk-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-RustDeskServer"
var_tags="${var_tags:-alpine;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  RELEASE=$(curl -s https://api.github.com/repos/lejianwen/rustdesk-server/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  msg_info "Installing RustDesk Server v${RELEASE}"
  temp_file1=$(mktemp)
  SERVER_ARCH=$(get_system_arch)
  [[ "$SERVER_ARCH" == "arm64" ]] && SERVER_ARCH="arm64v8"
  curl -fsSL "https://github.com/lejianwen/rustdesk-server/releases/download/${RELEASE}/rustdesk-server-linux-${SERVER_ARCH}.zip" -o "$temp_file1"
  $STD unzip "$temp_file1"
  mv "$SERVER_ARCH" /opt/rustdesk-server
  mkdir -p /root/.config/rustdesk
  cd /opt/rustdesk-server || exit
  ./rustdesk-utils genkeypair > /tmp/rustdesk_keys.txt
  grep "Public Key" /tmp/rustdesk_keys.txt | awk '{print $3}' > /root/.config/rustdesk/id_ed25519.pub
  grep "Secret Key" /tmp/rustdesk_keys.txt | awk '{print $3}' > /root/.config/rustdesk/id_ed25519
  chmod 600 /root/.config/rustdesk/id_ed25519
  chmod 644 /root/.config/rustdesk/id_ed25519.pub
  rm /tmp/rustdesk_keys.txt
  echo "${RELEASE}" > ~/.rustdesk-server
  msg_ok "Installed RustDesk Server v${RELEASE}"

  APIRELEASE=$(curl -s https://api.github.com/repos/lejianwen/rustdesk-api/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  msg_info "Installing RustDesk API v${APIRELEASE}"
  temp_file2=$(mktemp)
  curl -fsSL "https://github.com/lejianwen/rustdesk-api/releases/download/v${APIRELEASE}/linux-$(get_system_arch).tar.gz" -o "$temp_file2"
  $STD tar zxvf "$temp_file2"
  mv release /opt/rustdesk-api
  cd /opt/rustdesk-api || exit
  ADMINPASS=$(head -c 16 /dev/urandom | xxd -p -c 16)
  $STD ./apimain reset-admin-pwd "$ADMINPASS"
  cat << EOF > ~/rustdesk.creds
RustDesk WebUI

Username: admin
Password: $ADMINPASS
EOF
  echo "${APIRELEASE}" > ~/.rustdesk-api
  msg_ok "Installed RustDesk API v${APIRELEASE}"

  msg_info "Enabling RustDesk Server Services"
  cat << EOF > /etc/init.d/rustdesk-server-hbbs
#!/sbin/openrc-run
description="RustDesk HBBS Service"
directory="/opt/rustdesk-server"
command="/opt/rustdesk-server/hbbs"
command_args=""
command_background="true"
command_user="root"
pidfile="/var/run/rustdesk-server-hbbs.pid"
output_log="/var/log/rustdesk-hbbs.log"
error_log="/var/log/rustdesk-hbbs.err"

depend() {
    use net
}
EOF

  cat << EOF > /etc/init.d/rustdesk-server-hbbr
#!/sbin/openrc-run
description="RustDesk HBBR Service"
directory="/opt/rustdesk-server"
command="/opt/rustdesk-server/hbbr"
command_args=""
command_background="true"
command_user="root"
pidfile="/var/run/rustdesk-server-hbbr.pid"
output_log="/var/log/rustdesk-hbbr.log"
error_log="/var/log/rustdesk-hbbr.err"

depend() {
    use net
}
EOF

  cat << EOF > /etc/init.d/rustdesk-api
#!/sbin/openrc-run
description="RustDesk API Service"
directory="/opt/rustdesk-api"
command="/opt/rustdesk-api/apimain"
command_args=""
command_background="true"
command_user="root"
pidfile="/var/run/rustdesk-api.pid"
output_log="/var/log/rustdesk-api.log"
error_log="/var/log/rustdesk-api.err"

depend() {
    use net
}
EOF
  chmod +x /etc/init.d/rustdesk-server-hbbs
  chmod +x /etc/init.d/rustdesk-server-hbbr
  chmod +x /etc/init.d/rustdesk-api
  $STD rc-update add rustdesk-server-hbbs default
  $STD rc-update add rustdesk-server-hbbr default
  $STD rc-update add rustdesk-api default
  msg_ok "Enabled RustDesk Server Services"

  msg_info "Starting RustDesk Server"
  $STD service rustdesk-server-hbbs start
  $STD service rustdesk-server-hbbr start
  $STD service rustdesk-api start
  msg_ok "Started RustDesk Server"

  msg_info "Cleaning up"
  rm -f "$temp_file1" "$temp_file2"
  $STD apk cache clean
  msg_ok "Cleaned"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:21114${CL}"
  cat ~/rustdesk.creds
}

function update_script() {
  header_info
  if [[ ! -d /opt/rustdesk-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  APIRELEASE=$(curl -s https://api.github.com/repos/lejianwen/rustdesk-api/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  RELEASE=$(curl -s https://api.github.com/repos/lejianwen/rustdesk-server/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [ "${RELEASE}" != "$(cat ~/.rustdesk-server 2> /dev/null)" ] || [ ! -f ~/.rustdesk-server ]; then
    msg_info "Updating RustDesk Server to v${RELEASE}"
    $STD apk -U upgrade
    $STD service rustdesk-server-hbbs stop
    $STD service rustdesk-server-hbbr stop
    temp_file1=$(mktemp)
    SERVER_ARCH=$(get_system_arch)
    [[ "$SERVER_ARCH" == "arm64" ]] && SERVER_ARCH="arm64v8"
    curl -fsSL "https://github.com/lejianwen/rustdesk-server/releases/download/${RELEASE}/rustdesk-server-linux-${SERVER_ARCH}.zip" -o "$temp_file1"
    $STD unzip "$temp_file1"
    cp -r "$SERVER_ARCH"/* /opt/rustdesk-server/
    echo "${RELEASE}" > ~/.rustdesk-server
    $STD service rustdesk-server-hbbs start
    $STD service rustdesk-server-hbbr start
    rm -rf "$SERVER_ARCH"
    rm -f "$temp_file1"
    msg_ok "Updated RustDesk Server"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  if [ "${APIRELEASE}" != "$(cat ~/.rustdesk-api)" ] || [ ! -f ~/.rustdesk-api ]; then
    msg_info "Updating RustDesk API to v${APIRELEASE}"
    $STD service rustdesk-api stop
    temp_file2=$(mktemp)
    curl -fsSL "https://github.com/lejianwen/rustdesk-api/releases/download/v${APIRELEASE}/linux-$(get_system_arch).tar.gz" -o "$temp_file2"
    $STD tar zxvf "$temp_file2"
    cp -r release/* /opt/rustdesk-api
    echo "${APIRELEASE}" > ~/.rustdesk-api
    $STD service rustdesk-api start
    rm -rf release
    rm -f "$temp_file2"
    msg_ok "Updated RustDesk API"
  else
    msg_ok "No update required. RustDesk API is already at v${APIRELEASE}"
  fi
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
