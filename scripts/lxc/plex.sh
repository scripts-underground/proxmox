#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.plex.tv/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Plex"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Setting up Plex Media Server Repository"
  setup_deb822_repo \
    "plexmediaserver" \
    "https://downloads.plex.tv/plex-keys/PlexSign.v2.key" \
    "https://repo.plex.tv/deb/" \
    "public" \
    "main"
  msg_ok "Set up Plex Media Server Repository"

  msg_info "Installing Plex Media Server"
  $STD apt install -y plexmediaserver
  msg_ok "Installed Plex Media Server"

  setup_hwaccel "plex"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:32400/web${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -l plexmediaserver &> /dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # shellcheck disable=SC2155
  if [[ -f /etc/apt/sources.list.d/plexmediaserver.sources ]]; then
    local current_uri
    current_uri=$(grep -oP '(?<=URIs: ).*' /etc/apt/sources.list.d/plexmediaserver.sources 2> /dev/null || true)
    if [[ "$current_uri" == *"downloads.plex.tv/repo/deb"* ]]; then
      msg_info "Migrating to new Plex repository"
      rm -f /etc/apt/sources.list.d/plexmediaserver.sources
      rm -f /usr/share/keyrings/PlexSign.asc
      setup_deb822_repo \
        "plexmediaserver" \
        "https://downloads.plex.tv/plex-keys/PlexSign.v2.key" \
        "https://repo.plex.tv/deb/" \
        "public" \
        "main"
      msg_ok "Migrated to new Plex repository"
    fi
  elif compgen -G "/etc/apt/sources.list.d/plex*.list" > /dev/null; then
    msg_info "Migrating to new Plex repository (deb822)"
    rm -f /etc/apt/sources.list.d/plex*.list
    rm -f /usr/share/keyrings/PlexSign.asc
    rm -f /usr/share/keyrings/plexmediaserver.v2.gpg
    setup_deb822_repo \
      "plexmediaserver" \
      "https://downloads.plex.tv/plex-keys/PlexSign.v2.key" \
      "https://repo.plex.tv/deb/" \
      "public" \
      "main"
    msg_ok "Migrated to new Plex repository (deb822)"
  elif [[ ! -f /etc/apt/sources.list.d/plexmediaserver.sources ]]; then
    msg_info "Setting up Plex repository"
    setup_deb822_repo \
      "plexmediaserver" \
      "https://downloads.plex.tv/plex-keys/PlexSign.v2.key" \
      "https://repo.plex.tv/deb/" \
      "public" \
      "main"
    msg_ok "Set up Plex repository"
  fi
  if [[ -f /usr/local/bin/plexupdate ]] || [[ -d /opt/plexupdate ]]; then
    msg_info "Removing legacy plexupdate"
    rm -rf /opt/plexupdate /usr/local/bin/plexupdate
    crontab -l 2> /dev/null | grep -v plexupdate | crontab - 2> /dev/null || true
    msg_ok "Removed legacy plexupdate"
  fi

  msg_info "Updating Plex Media Server"
  $STD apt update
  $STD apt install -y plexmediaserver
  msg_ok "Updated Plex Media Server"

  msg_info "Restarting Plex Media Server"
  systemctl restart plexmediaserver
  msg_ok "Restarted Plex Media Server"

  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
