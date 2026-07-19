#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://asterisk.org

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Asterisk"
var_tags="${var_tags:-telephone;pbx}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    libsrtp2-dev \
    build-essential \
    libedit-dev \
    uuid-dev \
    libjansson-dev \
    libxml2-dev \
    libsqlite3-dev
  msg_ok "Installed Dependencies"

  msg_info "Fetching Asterisk Versions"
  ASTERISK_LIST=$(curl -fsSL https://downloads.asterisk.org/pub/telephony/asterisk/ |
    grep -oE 'asterisk-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' |
    sed 's/asterisk-//' |
    sed 's/\.tar\.gz//' |
    sort -V)
  LTS_VERSION=$(echo "$ASTERISK_LIST" | grep -E '^2(0|2|4|6)\.' | tail -n1 || true)
  STD_VERSION=$(echo "$ASTERISK_LIST" | grep -E '^2(1|3|5|7)\.' | tail -n1 || true)
  CERT_VERSION=$(curl -fsSL https://downloads.asterisk.org/pub/telephony/certified-asterisk/ |
    grep -oE 'asterisk-certified-[0-9]+\.[0-9]+-cert[0-9]+\.tar\.gz' |
    sed -E 's/asterisk-certified-//' |
    sed -E 's/\.tar\.gz//' |
    sort -V | tail -n1 || true)
  msg_ok "Fetched Versions"

  cat << EOF
Choose Asterisk version to install:
1) Latest Standard ($STD_VERSION)
2) Latest LTS ($LTS_VERSION)
3) Latest Certified ($CERT_VERSION)
EOF
  read -rp "Enter choice [1-3]: " ASTERISK_CHOICE

  CERTIFIED=0
  case "$ASTERISK_CHOICE" in
    2)
      ASTERISK_VERSION="$LTS_VERSION"
      ;;
    3)
      ASTERISK_VERSION="$CERT_VERSION"
      CERTIFIED=1
      ;;
    *)
      ASTERISK_VERSION="$STD_VERSION"
      ;;
  esac

  if [[ "$CERTIFIED" == "1" ]]; then
    RELEASE="asterisk-certified-${ASTERISK_VERSION}.tar.gz"
    DOWNLOAD_URL="https://downloads.asterisk.org/pub/telephony/certified-asterisk/$RELEASE"
  else
    RELEASE="asterisk-${ASTERISK_VERSION}.tar.gz"
    DOWNLOAD_URL="https://downloads.asterisk.org/pub/telephony/asterisk/$RELEASE"
  fi

  msg_info "Downloading Asterisk ($RELEASE)"
  temp_file=$(mktemp)
  curl -fsSL "$DOWNLOAD_URL" -o "$temp_file"
  mkdir -p /opt/asterisk
  tar zxf "$temp_file" --strip-components=1 -C /opt/asterisk
  cd /opt/asterisk || exit
  rm -f "$temp_file"
  msg_ok "Downloaded Asterisk ($RELEASE)"

  msg_info "Installing Asterisk"
  $STD ./contrib/scripts/install_prereq install
  $STD ./configure
  $STD make -j"$(nproc)"
  $STD make install
  $STD make config
  $STD make install-logrotate
  $STD make samples
  mkdir -p /etc/radiusclient-ng/
  ln /etc/radcli/radiusclient.conf /etc/radiusclient-ng/radiusclient.conf
  systemctl enable -q --now asterisk
  msg_ok "Installed Asterisk"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Asterisk PBX is now installed.${CL}"
  echo -e "${INFO}${YW}Configure SIP endpoints and extensions via CLI: asterisk -r${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  msg_error "No Update function provided for ${APP} LXC"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
