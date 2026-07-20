#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joseph Stubberfield (stubbers)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/librespeed/speedtest-rust

# shellcheck disable=SC2034
APP="Librespeed-Rust"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Librespeed-Rust"

  LIBRESPEED_ARCH="x86_64"
  [[ "$(get_system_arch)" == "arm64" ]] && LIBRESPEED_ARCH="aarch64"
  fetch_and_deploy_gh_release "librespeed-rust" "librespeed/speedtest-rust" "binary" "latest" "" "librespeed-rs-${LIBRESPEED_ARCH}-unknown-linux-gnu.deb"

  msg_info "Enabling Service"
  systemctl enable -q --now speedtest_rs
  msg_ok "Installed Librespeed-Rust"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/librespeed-rs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "librespeed-rust" "librespeed/speedtest-rust"; then
    msg_info "Stopping Services"
    systemctl stop speedtest_rs
    msg_ok "Services Stopped"

    LIBRESPEED_ARCH="x86_64"
    [[ "$(get_system_arch)" == "arm64" ]] && LIBRESPEED_ARCH="aarch64"
    fetch_and_deploy_gh_release "librespeed-rust" "librespeed/speedtest-rust" "binary" "latest" "" "librespeed-rs-${LIBRESPEED_ARCH}-unknown-linux-gnu.deb"

    msg_info "Starting Service"
    systemctl start speedtest_rs
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
