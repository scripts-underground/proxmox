#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.emqx.com/en

# shellcheck disable=SC2034
APP="EMQX"
var_tags="${var_tags:-mqtt}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"

  msg_info "Fetching latest EMQX Enterprise version"
  LATEST_VERSION=$(curl -fsSL https://www.emqx.com/en/downloads/enterprise | grep -oP '/en/downloads/enterprise/v\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1)
  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Failed to determine latest EMQX version"
    exit 250
  fi
  msg_ok "Latest version: v$LATEST_VERSION"

  DOWNLOAD_URL="https://www.emqx.com/en/downloads/enterprise/v$LATEST_VERSION/emqx-enterprise-${LATEST_VERSION}-debian12-$(get_system_arch).deb"
  DEB_FILE="/tmp/emqx-enterprise-${LATEST_VERSION}-debian12-$(get_system_arch).deb"

  msg_info "Downloading EMQX v$LATEST_VERSION"
  $STD curl -fsSL -o "$DEB_FILE" "$DOWNLOAD_URL"
  msg_ok "Downloaded EMQX"

  msg_info "Installing EMQX"
  $STD apt install -y "$DEB_FILE"
  rm -f "$DEB_FILE"
  echo "$LATEST_VERSION" > ~/.emqx
  msg_ok "Installed EMQX"

  read -r -p "${TAB3}Would you like to disable the EMQX MQ feature? (reduces disk/CPU usage) <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Disabling EMQX MQ feature"
    mkdir -p /etc/emqx
    if ! grep -q "^mq.enable" /etc/emqx/emqx.conf 2> /dev/null; then
      echo "mq.enable = false" >> /etc/emqx/emqx.conf
    else
      sed -i 's/^mq.enable.*/mq.enable = false/' /etc/emqx/emqx.conf
    fi
    msg_ok "Disabled EMQX MQ feature"
  fi

  msg_info "Starting EMQX"
  $STD systemctl enable -q --now emqx
  msg_ok "Started EMQX"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:18083${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  RELEASE=$(curl -fsSL https://www.emqx.com/en/downloads/enterprise | grep -oP '/en/downloads/enterprise/v\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1)
  if [[ "$RELEASE" != "$(cat ~/.emqx 2> /dev/null)" ]] || [[ ! -f ~/.emqx ]]; then
    msg_info "Stopping EMQX"
    systemctl stop emqx
    msg_ok "Stopped EMQX"

    msg_info "Removing old EMQX"
    if dpkg -l | grep -q "^ii\s\+emqx\s"; then
      $STD apt remove --purge -y emqx
    elif dpkg -l | grep -q "^ii\s\+emqx-enterprise\s"; then
      $STD apt remove --purge -y emqx-enterprise
    else
      msg_ok "No old EMQX package found"
    fi
    msg_ok "Removed old EMQX"

    msg_info "Downloading EMQX v${RELEASE}"
    $STD curl -fsSL -o "/tmp/emqx-enterprise-${RELEASE}-debian12-$(get_system_arch).deb" "https://www.emqx.com/en/downloads/enterprise/v${RELEASE}/emqx-enterprise-${RELEASE}-debian12-$(get_system_arch).deb"
    msg_ok "Downloaded EMQX"

    msg_info "Installing EMQX"
    $STD apt install -y "/tmp/emqx-enterprise-${RELEASE}-debian12-$(get_system_arch).deb"
    rm -f "/tmp/emqx-enterprise-${RELEASE}-debian12-$(get_system_arch).deb"
    echo "$RELEASE" > ~/.emqx
    msg_ok "Installed EMQX v${RELEASE}"

    msg_info "Starting EMQX"
    systemctl start emqx
    msg_ok "Started EMQX"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. EMQX is already at v${RELEASE}"
  fi

  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
