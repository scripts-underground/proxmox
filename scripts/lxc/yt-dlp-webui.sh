#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/marcopiovanello/yt-dlp-web-ui

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="yt-dlp-webui"
var_tags="${var_tags:-downloads;yt-dlp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  local ytdlp_asset="yt-dlp_linux"
  [[ "$(get_system_arch)" == "arm64" ]] && ytdlp_asset="yt-dlp_linux_aarch64"
  fetch_and_deploy_gh_release "yt-dlp-webui" "marcopiovanello/yt-dlp-web-ui" "singlefile" "latest" "/usr/local/bin" "yt-dlp-webui_linux-$(get_system_arch)"
  fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp" "singlefile" "latest" "/usr/local/bin" "$ytdlp_asset"

  msg_info "Setting up YT-DLP-WEBUI"
  mkdir -p /opt/yt-dlp-webui
  mkdir /downloads
  local RPC_PASSWORD
  RPC_PASSWORD=$(openssl rand -base64 16)
  cat << EOF > /opt/yt-dlp-webui/config.conf
# Host where server will listen at (default: "0.0.0.0")
#host: 0.0.0.0

# Port where server will listen at (default: 3033)
port: 3033

# Directory where downloaded files will be stored (default: ".")
downloadPath: /downloads

# [optional] Enable RPC authentication (requires username and password)
require_auth: true
username: admin
password: ${RPC_PASSWORD}

# [optional] The download queue size (default: logical cpu cores)
queue_size: 4 # min. 2

# [optional] Full path to the yt-dlp (default: "yt-dlp")
downloaderPath: /usr/local/bin/yt-dlp

# [optional] Enable file based logging with rotation (default: false)
#enable_file_logging: false

# [optional] Directory where the log file will be stored (default: ".")
#log_path: .

# [optional] Directory where the session database file will be stored (default: ".")
#session_file_path: .

# [optional] Path where the sqlite database will be created/opened (default: "./local.db")
#local_database_path

# [optional] Path where a custom frontend will be loaded (instead of the embedded one)
#frontend_path: ./web/solid-frontend
EOF
  cat << EOF > ~/yt-dlp-webui.creds
yt-dlp-webui-Credentials
Username: admin
Password: ${RPC_PASSWORD}
EOF
  msg_ok "Set up YT-DLP-WEBUI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/yt-dlp-webui.service
[Unit]
Description=yt-dlp-webui service file
After=network.target

[Service]
ExecStart=/usr/local/bin/yt-dlp-webui --conf /opt/yt-dlp-webui/config.conf

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now yt-dlp-webui
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3033${CL}"
  echo -e "${INFO}${YW} Credentials are stored in ~/yt-dlp-webui.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/yt-dlp-webui ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "yt-dlp-webui" "marcopiovanello/yt-dlp-web-ui"; then
    msg_info "Stopping Service"
    systemctl stop yt-dlp-webui
    msg_ok "Stopped Service"

    msg_info "Updating yt-dlp"
    $STD yt-dlp -U
    msg_ok "Updated yt-dlp"

    local ytdlp_asset="yt-dlp_linux"
    [[ "$(get_system_arch)" == "arm64" ]] && ytdlp_asset="yt-dlp_linux_aarch64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "yt-dlp-webui" "marcopiovanello/yt-dlp-web-ui" "singlefile" "latest" "/usr/local/bin" "yt-dlp-webui_linux-$(get_system_arch)"
    fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp" "singlefile" "latest" "/usr/local/bin" "$ytdlp_asset"

    msg_info "Starting Service"
    systemctl start yt-dlp-webui
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
