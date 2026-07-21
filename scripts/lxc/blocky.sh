#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://0xerr0r.github.io/blocky

# shellcheck disable=SC2034
APP="Blocky"
var_tags="${var_tags:-adblock}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "blocky" "0xERR0R/blocky" "prebuild" "latest" "/opt/blocky" "blocky_*_Linux_${ARCH}.tar.gz"

  msg_info "Configuring Blocky"
  if systemctl is-active systemd-resolved > /dev/null 2>&1; then
    systemctl disable -q --now systemd-resolved
  fi
  cat << 'EOF' > /opt/blocky/config.yml
upstreams:
  groups:
    default:
      - 1.1.1.1
      - tcp-tls:dns.quad9.net
blocking:
  denylists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  clientGroupsBlock:
    default:
      - ads
queryLog:
  type:
bootstrapDns:
  - upstream: tcp-tls:one.one.one.one
    ips:
      - 1.1.1.1
log:
  level: info
EOF
  msg_ok "Configured Blocky"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/blocky.service
[Unit]
Description=Blocky
After=network.target
[Service]
User=root
WorkingDirectory=/opt/blocky
ExecStart=/opt/blocky/./blocky --config config.yml
[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now blocky
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/blocky ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "blocky" "0xERR0R/blocky"; then
    msg_info "Stopping Service"
    systemctl stop blocky
    msg_ok "Stopped Service"
    create_backup /opt/blocky/config.yml
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "blocky" "0xERR0R/blocky" "prebuild" "latest" "/opt/blocky" "blocky_*_Linux_${ARCH}.tar.gz"
    restore_backup
    msg_info "Starting Service"
    systemctl start blocky
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
