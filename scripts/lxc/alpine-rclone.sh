#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://rclone.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-rclone"
var_tags="${var_tags:-alpine;storage}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing rclone"
  $STD apk add --no-cache rclone unzip
  msg_ok "Installed rclone"

  RELEASE=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  temp_file=$(mktemp)
  curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RELEASE}/rclone-v${RELEASE}-linux-$(get_system_arch).zip" -o "$temp_file"
  $STD unzip -j "$temp_file" '*/**' -d /opt/rclone
  cd /opt/rclone || exit

  RCLONE_PASSWORD=$(head -c 16 /dev/urandom | xxd -p -c 16)
  $STD htpasswd -cb -B /opt/login.pwd admin "$RCLONE_PASSWORD"
  cat << EOF > ~/rclone.creds
rclone-Credentials
rclone User Name: admin
rclone Password: $RCLONE_PASSWORD
EOF
  echo "${RELEASE}" > /opt/rclone_version.txt
  rm -f "$temp_file"
  msg_ok "Installed rclone"

  msg_info "Enabling rclone Service"
  cat << EOF > /etc/init.d/rclone
#!/sbin/openrc-run
description="rclone Service"
command="/opt/rclone/rclone"
command_args="rcd --rc-web-gui --rc-web-gui-no-open-browser --rc-addr :3000 --rc-htpasswd /opt/login.pwd"
command_background="true"
command_user="root"
pidfile="/var/run/rclone.pid"
depend() {
    use net
}
EOF
  chmod +x /etc/init.d/rclone
  $STD rc-update add rclone default
  msg_ok "Enabled rclone Service"
  msg_info "Starting rclone"
  $STD service rclone start
  msg_ok "Started rclone"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/rclone ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  RELEASE=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  curl -fsSL "https://github.com/rclone/rclone/releases/download/v${RELEASE}/rclone-v${RELEASE}-linux-$(get_system_arch).zip" -o /tmp/rclone.zip
  $STD unzip -o /tmp/rclone.zip '*/**' -d /opt/rclone
  echo "${RELEASE}" > /opt/rclone_version.txt
  rm -f /tmp/rclone.zip
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
