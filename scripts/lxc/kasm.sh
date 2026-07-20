#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.kasmweb.com/docs/latest/index.html

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Kasm"
var_tags="${var_tags:-workspace;remote-desktop}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"
var_fuse="${var_fuse:-yes}"
var_tun="${var_tun:-yes}"
var_kasm_version="${var_kasm_version:-1.19.0}"

function install_script() {
  msg_info "Installing Dependencies"
  setup_docker
  msg_ok "Installed Dependencies"

  msg_info "Detecting latest Kasm Workspaces release"
  KASM_URL=$(curl -s https://kasm.com/downloads |
    grep -oP 'https://kasm-static-content\.s3\.amazonaws\.com/kasm_release_\d+\.\d+\.\d+-latest\.tar\.gz' |
    head -1)
  KASM_VERSION=$(echo "$KASM_URL" | grep -oP '\d+\.\d+\.\d+(?=-latest)')

  if [[ -z "$KASM_VERSION" ]] || [[ -z "$KASM_URL" ]]; then
    msg_warn "Unable to fetch latest Kasm release online, falling back to v${var_kasm_version}"
  fi

  KASM_VERSION="${KASM_VERSION:-$var_kasm_version}"
  KASM_URL="${KASM_URL:-https://kasm-static-content.s3.amazonaws.com/kasm_release_${KASM_VERSION}-latest.tar.gz}"

  if [[ -z "$KASM_VERSION" ]] || [[ -z "$KASM_URL" ]]; then
    msg_error "Unable to detect latest Kasm release URL."
    exit 250
  fi
  msg_ok "Detected Kasm Workspaces version $KASM_VERSION"

  msg_warn "WARNING: This script will run an external installer from a third-party source (https://www.kasmweb.com/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  install.sh inside tar.gz $KASM_URL"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Installing Kasm Workspaces"
  curl_download "/opt/kasm_release_${KASM_VERSION}.tar.gz" "$KASM_URL"
  cd /opt || exit
  tar -xf "kasm_release_${KASM_VERSION}.tar.gz"
  chmod +x /opt/kasm_release/install.sh
  printf 'y\ny\ny\n4\n' | bash /opt/kasm_release/install.sh --ignore-dep-failures > ~/kasm-install.output 2>&1
  awk '
    /^Kasm UI Login Credentials$/ {capture=1}
    capture {print}
    /^Service Registration Token$/ {in_token=1}
    in_token && /^-+$/ {dash_count++}
    in_token && dash_count==2 {exit}
  ' ~/kasm-install.output > ~/kasm.creds
  rm -f "/opt/kasm_release_${KASM_VERSION}.tar.gz"
  rm -f ~/kasm-install.output
  msg_ok "Installed Kasm Workspaces"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
  echo -e "  ${YW}Admin Login:${CL}  ${GN}admin@kasm.local${CL}"
  echo -e "  ${YW}User Login:${CL}   ${GN}user@kasm.local${CL}"
  echo -e "  ${YW}Credentials:${CL}  ${GN}cat ~/kasm.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/kasm/current ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for new version"
  CURRENT_VERSION=$(readlink -f /opt/kasm/current | awk -F'/' '{print $4}')
  KASM_URL=$(curl -s https://kasm.com/downloads |
    grep -oP 'https://kasm-static-content\.s3\.amazonaws\.com/kasm_release_\d+\.\d+\.\d+-latest\.tar\.gz' |
    head -1)
  KASM_VERSION=$(echo "$KASM_URL" | grep -oP '\d+\.\d+\.\d+(?=-latest)')

  if [[ -z "$KASM_VERSION" ]] || [[ -z "$KASM_URL" ]]; then
    msg_warn "Unable to fetch latest Kasm release online, falling back to v${var_kasm_version}"
  fi

  KASM_VERSION="${KASM_VERSION:-$var_kasm_version}"
  KASM_URL="${KASM_URL:-https://kasm-static-content.s3.amazonaws.com/kasm_release_${KASM_VERSION}-latest.tar.gz}"

  if [[ -z "$KASM_VERSION" ]] || [[ -z "$KASM_URL" ]]; then
    msg_error "Unable to detect latest Kasm release URL."
    exit 250
  fi
  msg_ok "Checked for new version"

  msg_info "Removing outdated docker-compose plugin"
  [ -f ~/.docker/cli-plugins/docker-compose ] && rm -rf ~/.docker/cli-plugins/docker-compose
  msg_ok "Removed outdated docker-compose plugin"

  if [[ -z "$CURRENT_VERSION" ]] || [[ "$KASM_VERSION" != "$CURRENT_VERSION" ]]; then
    msg_info "Updating Kasm"
    cd /tmp || exit

    msg_warn "WARNING: This script will run an external installer from a third-party source (https://www.kasmweb.com/)."
    msg_warn "The following code is NOT maintained or audited by our repository."
    msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
    msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  upgrade.sh inside tar.gz $KASM_URL"
    echo
    read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      msg_error "Aborted by user. No changes have been made."
      exit 10
    fi
    curl_download "/tmp/kasm_release_${KASM_VERSION}.tar.gz" "$KASM_URL"
    tar -xf "kasm_release_${KASM_VERSION}.tar.gz"
    chmod +x /tmp/kasm_release/install.sh
    rm -f "/tmp/kasm_release_${KASM_VERSION}.tar.gz"

    bash /tmp/kasm_release/upgrade.sh --proxy-port 443
    rm -rf /tmp/kasm_release
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. Kasm is already at v${KASM_VERSION}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
