#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: chrisbenincasa
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://tunarr.com/ | https://github.com/chrisbenincasa/tunarr

# shellcheck disable=SC2034
APP="Tunarr"
var_tags="${var_tags:-iptv}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_gpu="${var_gpu:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_hwaccel

  msg_info "Fetching Tunarr"
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    TUN_ARCH="x64"
    FFM_ARCH="linux64"
  elif [ "$ARCH" = "aarch64" ]; then
    TUN_ARCH="arm64"
    FFM_ARCH="linuxarm64"
  fi
  fetch_and_deploy_gh_release "tunarr" "chrisbenincasa/tunarr" "prebuild" "latest" "/opt/tunarr" "*linux-${TUN_ARCH}.tar.gz"
  cd /opt/tunarr || exit
  mv tunarr* tunarr
  msg_ok "Fetched Tunarr"

  msg_info "Fetching ErsatzTV-ffmpeg"
  fetch_and_deploy_gh_release "ersatztv-ffmpeg" "ErsatzTV/ErsatzTV-ffmpeg" "prebuild" "latest" "/opt/ErsatzTV-ffmpeg" "*-${FFM_ARCH}-gpl-7.1.tar.xz"
  msg_ok "Fetched ErsatzTV-ffmpeg"

  msg_info "Setting ErsatzTV-ffmpeg links"
  chmod +x /opt/ErsatzTV-ffmpeg/bin/*
  ln -sf /opt/ErsatzTV-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
  ln -sf /opt/ErsatzTV-ffmpeg/bin/ffplay /usr/local/bin/ffplay
  ln -sf /opt/ErsatzTV-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
  msg_ok "Set ErsatzTV-ffmpeg links"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tunarr.service
[Unit]
Description=Tunarr Service
After=multi-user.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tunarr
ExecStart=/opt/tunarr/tunarr
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tunarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tunarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "tunarr" "chrisbenincasa/tunarr"; then
    msg_info "Stopping Tunarr"
    systemctl stop tunarr
    msg_ok "Stopped Tunarr"

    create_backup /root/.local/share/tunarr

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      TUN_ARCH="x64"
    elif [ "$ARCH" = "aarch64" ]; then
      TUN_ARCH="arm64"
    fi
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "tunarr" "chrisbenincasa/tunarr" "prebuild" "latest" "/opt/tunarr" "*linux-${TUN_ARCH}.tar.gz"
    cd /opt/tunarr || exit
    mv tunarr* tunarr
    restore_backup

    msg_info "Starting Tunarr"
    systemctl start tunarr
    msg_ok "Started Tunarr"
    msg_ok "Updated successfully!"
  fi

  if check_for_gh_release "ersatztv-ffmpeg" "ErsatzTV/ErsatzTV-ffmpeg"; then
    msg_info "Stopping Tunarr"
    systemctl stop tunarr
    msg_ok "Stopped Tunarr"

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
      FFM_ARCH="linux64"
    elif [ "$ARCH" = "aarch64" ]; then
      FFM_ARCH="linuxarm64"
    fi
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ersatztv-ffmpeg" "ErsatzTV/ErsatzTV-ffmpeg" "prebuild" "latest" "/opt/ErsatzTV-ffmpeg" "*-${FFM_ARCH}-gpl-7.1.tar.xz"

    msg_info "Setting ErsatzTV-ffmpeg links"
    chmod +x /opt/ErsatzTV-ffmpeg/bin/*
    ln -sf /opt/ErsatzTV-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
    ln -sf /opt/ErsatzTV-ffmpeg/bin/ffplay /usr/local/bin/ffplay
    ln -sf /opt/ErsatzTV-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
    msg_ok "Set ErsatzTV-ffmpeg links"

    msg_info "Starting Tunarr"
    systemctl start tunarr
    msg_ok "Started Tunarr"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
