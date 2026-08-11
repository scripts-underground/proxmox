#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2026 scripts-underground.org
# Author: Alex Indigo (alexindigo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/sentriz/gonic

# shellcheck disable=SC2034
APP="Gonic"
var_tags="${var_tags:-music;streaming}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_lxc_git_repo="${var_lxc_git_repo:-sentriz/gonic}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  local SYS_ARCH
  SYS_ARCH=$(get_system_arch)
  fetch_and_deploy_gh_release "gonic" "$var_lxc_git_repo" "binary" "latest" "/opt/gonic" "gonic_*_linux_${SYS_ARCH}.tar.gz"
  chmod +x /opt/gonic/gonic
  mkdir -p /opt/gonic/{music,cache,podcasts,playlists}

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gonic.service
[Unit]
Description=Gonic Music Streamer
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/gonic/gonic -music-path /opt/gonic/music -cache-path /opt/gonic/cache -podcast-path /opt/gonic/podcasts -playlist-path /opt/gonic/playlists -listen-addr :80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gonic
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW}Place your music files in /opt/gonic/music/ or mount your music library there.${CL}"
  echo -e "${INFO}${YW}Gonic scans the music directory on startup and serves via Subsonic API.${CL}"
}

function update_script() {
  render_header
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/gonic/gonic ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "gonic" "$var_lxc_git_repo"; then
    systemctl stop gonic
    local SYS_ARCH
    SYS_ARCH=$(get_system_arch)
    fetch_and_deploy_gh_release "gonic" "$var_lxc_git_repo" "binary" "latest" "/opt/gonic" "gonic_*_linux_${SYS_ARCH}.tar.gz"
    chmod +x /opt/gonic/gonic
    systemctl start gonic
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
