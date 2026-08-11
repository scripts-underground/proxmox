#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/netdata/netdata

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Netdata"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Netdata"
  curl -fsSL https://get.netdata.cloud/kickstart.sh | bash -s -- --non-interactive --disable-telemetry
  msg_ok "Installed Netdata"

  msg_info "Configuring Port 80"
  mkdir -p /etc/netdata
  cat << EOF > /etc/netdata/netdata.conf
[web]
    bind to = 0.0.0.0
    default port = 80
EOF
  systemctl restart netdata
  msg_ok "Configured Port 80"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/sbin/netdata ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  curl -fsSL https://get.netdata.cloud/kickstart.sh | bash -s -- --non-interactive --disable-telemetry --reinstall
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
