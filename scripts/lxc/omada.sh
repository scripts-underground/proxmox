#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.tp-link.com/us/support/download/omada-software-controller/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Omada"
var_tags="${var_tags:-tp-link;controller}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y jsvc
  msg_ok "Installed Dependencies"

  JAVA_VERSION="21" setup_java

  if [[ "$(dpkg --print-architecture)" == "arm64" ]] || lscpu | grep -q 'avx'; then
    MONGO_VERSION="8.0" setup_mongodb
  else
    msg_error "No AVX detected (CPU-Flag)! We have discontinued support for this. You are welcome to try it manually with a Debian LXC, but due to the many issues with Omada, we currently only support AVX CPUs."
    exit 10
  fi

  if ! dpkg -l | grep -q 'libssl1.1'; then
    msg_info "Installing libssl (if needed)"
    curl_download "/tmp/libssl.deb" "https://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1w-0+deb11u8_$(dpkg --print-architecture).deb"
    $STD dpkg -i /tmp/libssl.deb
    rm -f /tmp/libssl.deb
    msg_ok "Installed libssl1.1"
  fi

  msg_info "Installing Omada Controller"
  OMADA_URL=$(curl -fsSL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15" "https://support.omadanetworks.com/en/download/software/omada-controller/" |
    grep -o 'https://static\.tp-link\.com/upload/software/[^"]*linux_x64[^"]*\.deb' |
    head -n1)
  OMADA_PKG=$(basename "${OMADA_URL}")
  curl_download "${OMADA_PKG}" "${OMADA_URL}"
  $STD dpkg -i "${OMADA_PKG}"
  rm -rf "${OMADA_PKG}"
  VERSION=$(sed -n 's/.*_v\([0-9.]*\)_linux.*/\1/p' <<< "${OMADA_PKG}")
  echo "${VERSION}" > $HOME/.omada
  msg_ok "Installed Omada Controller"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8043${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tplink ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating MongoDB"
  if [[ "$(dpkg --print-architecture)" == "arm64" ]] || lscpu | grep -q 'avx'; then
    # shellcheck disable=SC2034
    MONGO_VERSION="8.0"
  else
    msg_error "No AVX detected (CPU-Flag)! We have discontinued support for this. You are welcome to try it manually with a Debian LXC, but due to the many issues with Omada, we currently only support AVX CPUs."
    exit 10
  fi

  JAVA_VERSION="21" setup_java

  OMADA_URL=$(curl -fsSL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15" "https://support.omadanetworks.com/en/download/software/omada-controller/" |
    grep -o 'https://static\.tp-link\.com/upload/software/[^"]*linux_x64[^"]*\.deb' |
    head -n1)
  OMADA_PKG=$(basename "${OMADA_URL}")
  VERSION=$(sed -n 's/.*_v\([0-9.]*\)_linux.*/\1/p' <<< "${OMADA_PKG}")

  CURRENT_VERSION=$(cat $HOME/.omada 2> /dev/null || echo "0")

  if dpkg --compare-versions "${VERSION}" gt "${CURRENT_VERSION}"; then

    msg_info "Updating Omada Controller"

    if [ -z "${OMADA_PKG}" ]; then
      msg_error "Could not retrieve Omada package – server may be down."
      exit
    fi
    curl -fsSL "${OMADA_URL}" -o "${OMADA_PKG}"
    export DEBIAN_FRONTEND=noninteractive
    $STD dpkg -i "${OMADA_PKG}"
    rm -f "${OMADA_PKG}"
    echo "${VERSION}" > $HOME/.omada
    msg_ok "Updated Omada Controller to ${VERSION}"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update available: ${APP} (${CURRENT_VERSION})"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
