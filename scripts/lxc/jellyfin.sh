#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://jellyfin.org/

APP="Jellyfin"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /usr/lib/jellyfin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if ! grep -qEi 'ubuntu' /etc/os-release; then
    msg_info "Updating Intel Dependencies"
    rm -f ~/.intel-* || true

    fetch_and_deploy_gh_release "intel-libgdgmm12" "intel/compute-runtime" "binary" "latest" "" "libigdgmm12_*_amd64.deb"

    local igc_tag
    _resolve_igc_tag igc_tag

    fetch_and_deploy_gh_release "intel-igc-core-2" "intel/intel-graphics-compiler" "binary" "$igc_tag" "" "intel-igc-core-2_*_amd64.deb"
    fetch_and_deploy_gh_release "intel-igc-opencl-2" "intel/intel-graphics-compiler" "binary" "$igc_tag" "" "intel-igc-opencl-2_*_amd64.deb"
    fetch_and_deploy_gh_release "intel-opencl-icd" "intel/compute-runtime" "binary" "latest" "" "intel-opencl-icd_*_amd64.deb"
    msg_ok "Updated Intel Dependencies"
  fi

  msg_info "Setting up Jellyfin Repository"
  setup_deb822_repo \
    "jellyfin" \
    "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
    "https://repo.jellyfin.org/$(get_os_info id)" \
    "$(get_os_info codename)"
  msg_ok "Set up Jellyfin Repository"

  msg_info "Updating Jellyfin"
  ensure_dependencies libjemalloc2
  if [[ ! -f /usr/lib/libjemalloc.so ]]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/lib/libjemalloc.so
  fi
  $STD apt -y upgrade
  $STD apt -y --with-new-pkgs upgrade jellyfin jellyfin-server jellyfin-ffmpeg7
  ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
  ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe
  msg_ok "Updated Jellyfin"
  msg_ok "Updated successfully!"
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_custom "ℹ️" "${GN}" "If NVIDIA GPU passthrough is detected, you'll be asked whether to install drivers in the container"

  msg_info "Installing Dependencies"
  ensure_dependencies libjemalloc2
  if [[ ! -f /usr/lib/libjemalloc.so ]]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/lib/libjemalloc.so
  fi
  msg_ok "Installed Dependencies"

  msg_info "Setting up Jellyfin Repository"
  setup_deb822_repo \
    "jellyfin" \
    "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
    "https://repo.jellyfin.org/$(get_os_info id)" \
    "$(get_os_info codename)"
  msg_ok "Set up Jellyfin Repository"

  msg_info "Installing Jellyfin"
  $STD apt install -y jellyfin jellyfin-ffmpeg7
  ln -sf /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin/ffmpeg
  ln -sf /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin/ffprobe
  msg_ok "Installed Jellyfin"

  setup_hwaccel "jellyfin"

  msg_info "Configuring Jellyfin"
  # Configure log rotation to prevent disk fill (keeps fail2ban compatibility) (PR: #1690 / Issue: #11224)
  cat <<EOF >/etc/logrotate.d/jellyfin
/var/log/jellyfin/*.log {
    daily
    rotate 3
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
  chown -R jellyfin:adm /etc/jellyfin
  sleep 10
  systemctl restart jellyfin
  msg_ok "Configured Jellyfin"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8096${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
