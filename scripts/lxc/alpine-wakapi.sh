#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://wakapi.dev/ | https://github.com/muety/wakapi

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Wakapi"
var_tags="${var_tags:-code;time-tracking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache \
    ca-certificates \
    tzdata
  $STD update-ca-certificates
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "wakapi" "muety/wakapi" "prebuild" "latest" "/opt/wakapi" "wakapi_linux_$(get_system_arch).zip"

  msg_info "Configuring Wakapi"
  LOCAL_IP=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
  cd /opt/wakapi || exit
  sed -i 's/listen_ipv6: ::1/listen_ipv6: "-"/g' config.yml
  sed -i 's/listen_ipv4: 127.0.0.1/listen_ipv4: "0.0.0.0"/g' config.yml
  sed -i "s/public_url: http:\/\/localhost:3000/public_url: http:\/\/$LOCAL_IP:3000/g" config.yml
  msg_ok "Configured Wakapi"

  msg_info "Enabling Wakapi Service"
  cat << EOF > /etc/init.d/wakapi
#!/sbin/openrc-run
description="Wakapi Service"
directory="/opt/wakapi"
command="/opt/wakapi/wakapi"
command_args="-config config.yml"
command_background="true"
command_user="root"
pidfile="/var/run/wakapi.pid"

depend() {
    use net
}
EOF
  chmod +x /etc/init.d/wakapi
  $STD rc-update add wakapi default
  msg_ok "Enabled Wakapi Service"

  msg_info "Starting Wakapi"
  $STD rc-service wakapi start
  msg_ok "Started Wakapi"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/wakapi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/muety/wakapi/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [ "${RELEASE}" != "$(cat ~/.wakapi 2> /dev/null)" ] || [ ! -f ~/.wakapi ]; then
    msg_info "Stopping Wakapi Service"
    $STD rc-service wakapi stop
    msg_ok "Stopped Wakapi Service"

    msg_info "Updating Wakapi LXC"
    $STD apk -U upgrade
    msg_ok "Updated Wakapi LXC"

    msg_info "Creating backup"
    mkdir -p /opt/wakapi-backup
    cp /opt/wakapi/config.yml /opt/wakapi/wakapi_db.db /opt/wakapi-backup/
    msg_ok "Created backup"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wakapi" "muety/wakapi" "prebuild" "latest" "/opt/wakapi" "wakapi_linux_$(get_system_arch).zip"

    msg_info "Configuring Wakapi"
    cd /opt/wakapi || exit
    cp /opt/wakapi-backup/config.yml /opt/wakapi/
    cp /opt/wakapi-backup/wakapi_db.db /opt/wakapi/
    rm -rf /opt/wakapi-backup
    msg_ok "Configured Wakapi"

    msg_info "Starting Service"
    $STD rc-service wakapi start
    msg_ok "Started Service"
    msg_ok "Updated successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
