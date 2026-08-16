#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.webmin.com/ | Github: https://github.com/webmin/webmin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Webmin"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_pkg="${var_addon_pkg:-webmin}"
var_addon_service="${var_addon_service:-webmin}"
var_addon_gh_repo="${var_addon_gh_repo:-webmin/webmin}"
var_addon_default_port="${var_addon_default_port:-10000}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  msg_info "Installing Prerequisites"
  $STD apt update
  $STD apt install -y \
    libnet-ssleay-perl \
    libauthen-pam-perl \
    libio-pty-perl \
    unzip \
    shared-mime-info
  msg_ok "Installed Prerequisites"

  msg_info "Installing ${APP}"
  fetch_and_deploy_gh_release "$var_addon_pkg" "$var_addon_gh_repo" "binary" "latest" "/opt/webmin" "webmin_*_all.deb"
  /usr/share/webmin/changepass.pl /etc/webmin root root &> /dev/null
  msg_ok "Installed ${APP}"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Web UI:${CL} ${BGN}https://${LOCAL_IP}:${var_addon_default_port}${CL}"
  echo -e "${INFO}${YW}Login:${CL} ${GN}root${CL} / ${GN}root${CL} (change via Webmin Configuration)"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  if check_for_gh_release "$var_addon_pkg" "$var_addon_gh_repo"; then
    msg_info "Updating ${APP}"
    fetch_and_deploy_gh_release "$var_addon_pkg" "$var_addon_gh_repo" "binary" "latest" "/opt/webmin" "webmin_*_all.deb"
    systemctl restart "$var_addon_service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  systemctl disable --now "$var_addon_service" &> /dev/null || true
  $STD apt remove -y "$var_addon_pkg"
  rm -f "$HOME/.${var_addon_pkg}"
  msg_ok "${APP} has been uninstalled"
}

# Addons run inside arbitrary containers that may lack curl — ensure the
# transport before sourcing the framework (everything else is bootstrapped
# by install.func from this point on)
if ! command -v curl > /dev/null 2>&1; then
  if [[ -f /etc/alpine-release ]]; then
    apk update &> /dev/null && apk add --no-cache curl &> /dev/null
  else
    apt-get update &> /dev/null && apt-get install -y curl &> /dev/null
  fi
fi
command -v curl > /dev/null 2>&1 || {
  echo "FATAL: curl is required and could not be installed" >&2
  exit 1
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon")
