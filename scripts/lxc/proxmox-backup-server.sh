#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.proxmox.com/en/proxmox-backup-server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Proxmox-Backup-Server"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  export DEBIAN_FRONTEND=noninteractive
  export IFUPDOWN2_NO_IFRELOAD=1

  if [[ "$(get_system_arch)" == "arm64" ]]; then
    msg_info "Installing Proxmox Backup Server (unofficial arm64 build)"
    PBS_TMP=$(mktemp -d)
    github_api_call "https://api.github.com/repos/wofferl/proxmox-backup-arm64/releases/latest" "$PBS_TMP/release.json"
    cd "$PBS_TMP" || exit
    for url in $(jq -r '.assets[].browser_download_url
      | select(endswith(".deb"))
      | select(test("dbgsym|client-static|file-restore") | not)' "$PBS_TMP/release.json"); do
      curl_with_retry "$url" "$(basename "$url")"
    done
    $STD apt install -y ./*.deb
    rm -rf "$PBS_TMP"
  else
    msg_info "Installing Proxmox Backup Server"
    setup_deb822_repo \
      "proxmox-backup-server" \
      "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg" \
      "http://download.proxmox.com/debian/pbs" \
      "trixie" \
      "pbs-no-subscription"
    $STD apt install -y proxmox-backup-server
  fi
  msg_ok "Installed Proxmox Backup Server"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8007${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -e /usr/sbin/proxmox-backup-manager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated $APP LXC"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
