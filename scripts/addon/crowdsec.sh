#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.crowdsec.net/ | Github: https://github.com/crowdsecurity/crowdsec

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CrowdSec"

# Bundle-consumed configuration (var_addon_* is baked into update/uninstall
# bundles at install time — hooks may reference these directly)
var_addon_pkg="${var_addon_pkg:-crowdsec}"
var_addon_bouncer_pkg="${var_addon_bouncer_pkg:-crowdsec-firewall-bouncer-iptables}"
var_addon_repo_list="${var_addon_repo_list:-/etc/apt/sources.list.d/crowdsec_crowdsec.list}"

function install_script() {
  if [[ "$OS_FAMILY" != "debian" ]]; then
    msg_error "Unsupported OS: ${OS_TYPE} (Debian/Ubuntu only)"
    exit 1
  fi

  msg_info "Setting up ${APP} Repository"
  $STD apt update
  $STD apt install -y curl gnupg
  $STD bash -c "curl -fsSL https://install.crowdsec.net | bash"
  msg_ok "Setup ${APP} Repository"

  msg_info "Installing ${APP}"
  $STD apt update
  $STD apt install -y "$var_addon_pkg"
  msg_ok "Installed ${APP}"

  msg_info "Installing ${APP} Firewall Bouncer"
  $STD apt install -y "$var_addon_bouncer_pkg"
  msg_ok "Installed ${APP} Firewall Bouncer"
}

function post_install_script() {
  echo ""
  msg_ok "${APP} installed successfully"
  echo -e "${INFO}${YW}Local API:${CL} ${BGN}http://${LOCAL_IP}:8080${CL}"
  echo -e "${INFO}${YW}Update:${CL} update-${APP_SLUG}   ${YW}Uninstall:${CL} uninstall-${APP_SLUG}"
}

function update_script() {
  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt install --only-upgrade -y "$var_addon_pkg" "$var_addon_bouncer_pkg"
  msg_ok "Updated successfully!"
  exit
}

function uninstall_script() {
  msg_info "Uninstalling ${APP}"
  $STD apt remove --purge -y "$var_addon_pkg" "$var_addon_bouncer_pkg"
  rm -f "$var_addon_repo_list"
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
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
