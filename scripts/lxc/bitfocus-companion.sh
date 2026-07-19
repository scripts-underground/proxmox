#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: glabutis
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bitfocus/companion

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Bitfocus-Companion"
var_tags="${var_tags:-automation;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libusb-1.0-0
  msg_ok "Installed Dependencies"

  msg_info "Fetching Latest Bitfocus Companion Release"
  COMPANION_ARCH=$(uname -m)
  [[ "$COMPANION_ARCH" == "x86_64" ]] && COMPANION_ARCH="x64"
  [[ "$COMPANION_ARCH" == "aarch64" ]] && COMPANION_ARCH="arm64"
  COMPANION_TARGET=$(uname -m)
  [[ "$COMPANION_TARGET" == "x86_64" ]] && COMPANION_TARGET="tgz"
  [[ "$COMPANION_TARGET" == "aarch64" ]] && COMPANION_TARGET="arm64-tgz"
  RELEASE_JSON=$(curl -fsSL "https://api.bitfocus.io/v1/product/companion/packages?limit=20")
  PACKAGE_JSON=$(echo "$RELEASE_JSON" | jq -c \
    --arg target "linux-${COMPANION_TARGET}" \
    --arg arch "linux-${COMPANION_ARCH}" \
    '(if type == "array" then . else .packages end) | [.[] | select(.target==$target and (.uri | contains($arch)))] | first')
  RELEASE=$(echo "$PACKAGE_JSON" | jq -r '.version // empty')
  ASSET_URL=$(echo "$PACKAGE_JSON" | jq -r '.uri // empty')
  if [[ -z "$RELEASE" || -z "$ASSET_URL" ]]; then
    msg_error "Could not resolve a matching Linux ${COMPANION_ARCH} Companion package from the Bitfocus API."
    exit
  fi
  msg_ok "Found Companion ${RELEASE}"

  fetch_and_deploy_from_url "$ASSET_URL" "/opt/bitfocus-companion"

  msg_info "Installing udev Rules"
  if [[ -f /opt/bitfocus-companion/50-companion-headless.rules ]]; then
    cp /opt/bitfocus-companion/50-companion-headless.rules /etc/udev/rules.d/
    udevadm control --reload-rules
    udevadm trigger
  fi
  msg_ok "Installed udev Rules"

  mkdir -p /opt/bitfocus-companion-config

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bitfocus-companion.service
[Unit]
Description=Bitfocus Companion
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/bitfocus-companion/companion_headless.sh --config-dir /opt/bitfocus-companion-config
WorkingDirectory=/opt/bitfocus-companion
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bitfocus-companion
  msg_ok "Created Service"

  echo "${RELEASE}" > ~/.bitfocus-companion
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/bitfocus-companion/companion_headless.sh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  COMPANION_ARCH=$(uname -m)
  [[ "$COMPANION_ARCH" == "x86_64" ]] && COMPANION_ARCH="x64"
  [[ "$COMPANION_ARCH" == "aarch64" ]] && COMPANION_ARCH="arm64"
  COMPANION_TARGET=$(uname -m)
  [[ "$COMPANION_TARGET" == "x86_64" ]] && COMPANION_TARGET="tgz"
  [[ "$COMPANION_TARGET" == "aarch64" ]] && COMPANION_TARGET="arm64-tgz"
  RELEASE_JSON=$(curl -fsSL "https://api.bitfocus.io/v1/product/companion/packages?limit=20")
  PACKAGE_JSON=$(echo "$RELEASE_JSON" | jq -c \
    --arg target "linux-${COMPANION_TARGET}" \
    --arg arch "linux-${COMPANION_ARCH}" \
    '(if type == "array" then . else .packages end) | [.[] | select(.target==$target and (.uri | contains($arch)))] | first')
  RELEASE=$(echo "$PACKAGE_JSON" | jq -r '.version // empty')
  ASSET_URL=$(echo "$PACKAGE_JSON" | jq -r '.uri // empty')
  if [[ -z "$RELEASE" || -z "$ASSET_URL" ]]; then
    msg_error "Could not resolve a matching Linux ${COMPANION_ARCH} Companion package from the Bitfocus API."
    exit
  fi

  if [[ "${RELEASE}" == "$(cat ~/.bitfocus-companion 2> /dev/null)" ]]; then
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
    exit
  fi

  msg_info "Stopping ${APP}"
  systemctl stop bitfocus-companion
  msg_ok "Stopped ${APP}"

  msg_info "Updating ${APP} to v${RELEASE}"
  CLEAN_INSTALL=1 fetch_and_deploy_from_url "$ASSET_URL" "/opt/bitfocus-companion"
  echo "${RELEASE}" > ~/.bitfocus-companion
  msg_ok "Updated ${APP} to v${RELEASE}"

  msg_info "Starting ${APP}"
  systemctl start bitfocus-companion
  msg_ok "Started ${APP}"

  msg_ok "Update Successful"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
